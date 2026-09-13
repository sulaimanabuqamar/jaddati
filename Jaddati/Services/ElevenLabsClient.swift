import Foundation

/// Direct client for the two ElevenLabs endpoints this app uses.
///
///   POST /v1/voices/add                 multipart: name, files  -> { voice_id, requires_verification }
///   POST /v1/text-to-speech/{voice_id}  json: { text, model_id } -> mp3 bytes
struct ElevenLabsClient: VoiceService {

    private let base: URL
    private let key: String

    /// One session for the whole app. A fresh URLSession per request throws away
    /// the connection pool and pays a new TLS handshake on every generation —
    /// straight onto the latency the audience is watching.
    private static let shared: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = AppConfig.requestTimeout
        config.timeoutIntervalForResource = AppConfig.requestTimeout * 2
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    init(key: String = AppConfig.elevenLabsKey,
         base: URL = URL(string: AppConfig.voiceBaseURL) ?? URL(string: "https://api.elevenlabs.io")!) {
        self.key = key
        self.base = base
    }

    /// Who is asking, for the three calls the relay charges somebody for.
    ///
    /// Hung off the same test as the device header: a build pointed straight at
    /// ElevenLabs with its own key is spending its own money and owes nobody
    /// here an account. That is what leaves the demo phone untouched by all of
    /// this — it carries its own key and never goes through the relay.
    private func accountToken(_ refusal: String) async throws -> String {
        guard AppConfig.sendsVoiceDeviceHeader else { return "" }
        guard let token = await CloudBackup.shared.accountToken() else {
            throw VoiceServiceError.signInRequired(refusal)
        }
        return token
    }

    private static var signInToGenerate: String {
        L("Sign in with Google to make new audio. The button is in Backup, on the You tab.")
    }

    /// Adds it, if there is one to add.
    private func sign(_ request: inout URLRequest, with account: String) {
        guard !account.isEmpty else { return }
        request.setValue(account, forHTTPHeaderField: "X-Jaddati-Account")
    }

    // MARK: Voice creation

    func createVoice(name: String, sampleURL: URL) async throws -> CreatedVoice {
        guard Consent.networkAllowed else { throw ConsentMissing() }
        guard !key.isEmpty else { throw VoiceServiceError.notConfigured }

        let sampleData: Data
        do { sampleData = try Data(contentsOf: sampleURL) }
        catch { throw VoiceServiceError.sampleUnreadable }

        // Only catches a truncated or empty file. Whether the recording is long
        // enough is a question about seconds, and it is asked in the UI where
        // the duration is actually known.
        guard sampleData.count > 5_000 else { throw VoiceServiceError.sampleUnreadable }

        // The docs render the field as `files[]`; the curl examples use `files`.
        // Try the common spelling, and fall back rather than failing the demo
        // over a bracket.
        do {
            return try await postVoice(name: name, data: sampleData,
                                       filename: sampleURL.lastPathComponent,
                                       mime: mimeType(for: sampleURL), field: "files")
        } catch let error as VoiceServiceError {
            switch error {
            case .sampleRejected:
                // The server refused the shape of the request, which is exactly
                // what a wrong multipart field name looks like. Try the other
                // spelling before giving up.
                //
                // Deliberately NOT retrying .badResponse: that is also thrown
                // for a 2xx body we could not parse, where the voice very
                // likely WAS created. Retrying would mint a second one and
                // spend another slot.
                return try await retryVoice(name: name, data: sampleData, url: sampleURL)
            default:
                throw error
            }
        }
    }

    /// Second attempt with the bracketed field name the API reference shows.
    private func retryVoice(name: String, data: Data, url: URL) async throws -> CreatedVoice {
        try await postVoice(name: name, data: data,
                            filename: url.lastPathComponent,
                            mime: mimeType(for: url), field: "files[]")
    }

    private func postVoice(name: String, data: Data, filename: String,
                           mime: String, field: String) async throws -> CreatedVoice {
        // Asked before the recording is packed into a multipart body, so that
        // somebody who is not signed in hears about it in the second it takes
        // to check rather than after a megabyte has gone up the wire.
        let account = try await accountToken(Self.signInToGenerate)

        let boundary = "jaddati.\(UUID().uuidString)"
        var request = URLRequest(url: base.appendingPathComponent("v1/voices/add"))
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        if AppConfig.sendsVoiceDeviceHeader {
            request.setValue(AppConfig.deviceId, forHTTPHeaderField: "X-Jaddati-Device")
        }
        sign(&request, with: account)
        request.setValue("multipart/form-data; boundary=\(boundary)",
                         forHTTPHeaderField: "Content-Type")

        var body = Data()
        func append(_ string: String) { body.append(Data(string.utf8)) }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"name\"\r\n\r\n")
        append("\(name)\r\n")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(field)\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mime)\r\n\r\n")
        body.append(data)
        append("\r\n--\(boundary)--\r\n")
        request.httpBody = body

        let (responseData, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse else { throw VoiceServiceError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw mapError(status: http.statusCode, body: responseData)
        }
        guard let object = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let voiceId = object["voice_id"] as? String, !voiceId.isEmpty else {
            throw VoiceServiceError.badResponse
        }
        return CreatedVoice(id: voiceId,
                            requiresVerification: (object["requires_verification"] as? Bool) ?? false)
    }

    // MARK: Speech

    func synthesize(text: String, voiceId: String, modelId: String,
                    tuning: VoiceTuning) async throws -> Data {
        guard Consent.networkAllowed else { throw ConsentMissing() }
        guard !key.isEmpty else { throw VoiceServiceError.notConfigured }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Refused before anything is spent — no credit, no slot, no upstream
        // call. The relay checks the same list, because this one is only the
        // polite half: the web build is readable and the phone can be pointed
        // anywhere, so a check that lives only in a client is a suggestion.
        if BlockedWords.refusal(in: trimmed) != nil { throw VoiceServiceError.refused }

        // Measured on what was typed, not on what is sent. The break tags below
        // are the app's doing and should not eat someone's allowance.
        guard trimmed.count <= AppConfig.maxCharactersPerGeneration else {
            throw VoiceServiceError.textTooLong(limit: AppConfig.maxCharactersPerGeneration)
        }

        // Before the harakat call, not after: that one is a round trip to a
        // model of its own, and spending it on a sentence about to be refused
        // for want of a sign-in is a wait that buys nothing.
        let account = try await accountToken(Self.signInToGenerate)

        // Marks first, then pauses. The other order hands `<break time="0.9s" />`
        // to a model that has just been told to put a vowel on every letter.
        let vowelled = await TashkeelService().vowelled(trimmed)
        let spoken = SpokenText.withParagraphPauses(vowelled)

        var components = URLComponents(
            url: base.appendingPathComponent("v1/text-to-speech/\(voiceId)"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "output_format", value: "mp3_44100_128")]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        if AppConfig.sendsVoiceDeviceHeader {
            request.setValue(AppConfig.deviceId, forHTTPHeaderField: "X-Jaddati-Device")
        }
        sign(&request, with: account)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        // Both dictionaries are annotated. `data(withJSONObject:)` takes `Any`,
        // which gives the literals no contextual type, and a literal mixing
        // Double and Bool then has nothing to infer from.
        let settings: [String: Any] = [
            "stability": tuning.stability,
            "similarity_boost": tuning.similarity,
            "style": tuning.style,
            "use_speaker_boost": tuning.speakerBoost,
            "speed": tuning.speed
        ]
        let payload: [String: Any] = [
            "text": spoken,
            "model_id": modelId,
            "voice_settings": settings
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse else { throw VoiceServiceError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw mapError(status: http.statusCode, body: data, kind: .speech)
        }
        guard data.count > 500 else { throw VoiceServiceError.badResponse }
        return data
    }

    // MARK: Deletion

    func deleteVoice(voiceId: String) async throws {
        // First, above everything. A voice minted by the offline test mode never
        // existed at the provider, so there is nothing to refuse on consent
        // grounds and nothing a missing key could have stopped. Checking those
        // first told people a voice would be left behind that was never there.
        guard !voiceId.hasPrefix(AppConfig.placeholderVoicePrefix) else { return }
        guard Consent.networkAllowed else { throw ConsentMissing() }
        guard !key.isEmpty else { throw VoiceServiceError.notConfigured }

        // The relay will not take a deletion from nobody either: it has to know
        // the slot being given up is the one this account is holding.
        let account = try await accountToken(
            L("Sign in with Google to take this voice back off the voice service. The button is in Backup, on the You tab."))

        var request = URLRequest(url: base.appendingPathComponent("v1/voices/\(voiceId)"))
        request.httpMethod = "DELETE"
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        if AppConfig.sendsVoiceDeviceHeader {
            request.setValue(AppConfig.deviceId, forHTTPHeaderField: "X-Jaddati-Device")
        }
        sign(&request, with: account)

        let (data, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse else { throw VoiceServiceError.badResponse }
        // Already gone is the outcome we wanted.
        if http.statusCode == 404 { return }
        guard (200..<300).contains(http.statusCode) else {
            throw mapError(status: http.statusCode, body: data, kind: .voiceCreation)
        }
    }

    // MARK: Plumbing

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await ElevenLabsClient.shared.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .timedOut:
                throw VoiceServiceError.timedOut
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
                 .cannotConnectToHost, .dataNotAllowed, .internationalRoamingOff:
                throw VoiceServiceError.offline
            case .cancelled:
                throw VoiceServiceError.timedOut
            default:
                throw VoiceServiceError.provider(status: error.code.rawValue,
                                                 detail: error.localizedDescription)
            }
        } catch {
            // Anything non-URLError must not escape untyped — the UI would show
            // a Swift error description to a judge.
            throw VoiceServiceError.provider(status: -1, detail: error.localizedDescription)
        }
    }

    /// Which endpoint an error came from. The same status code means different
    /// things on each, and reporting the wrong one sends the reader to the
    /// wrong problem.
    private enum CallKind { case voiceCreation, speech }

    /// Turns a provider status code into something a person can act on.
    ///
    /// Quota and voice-slot exhaustion are checked BEFORE the status switch:
    /// ElevenLabs reports credit exhaustion as 401, and treating that as a bad
    /// key sends you debugging the wrong thing while the judges wait.
    private func mapError(status: Int, body: Data, kind: CallKind = .voiceCreation) -> VoiceServiceError {
        let detail = extractDetail(body)
        let lowered = detail.lowercased()

        if lowered.contains("quota") || lowered.contains("credit") || lowered.contains("exceeded") {
            return .outOfCredits
        }
        // Checked before the account-full test on purpose: the relay says this
        // when the signed-in account is itself holding the slot, and sending
        // someone to go free up an account they do not own is the wrong
        // instruction when the thing to remove is on screen in front of them.
        if lowered.contains("this account already has a voice") {
            return .deviceAlreadyHasVoice
        }
        // The relay meters by account now, so its 401 means nobody is signed
        // in — not that a key was refused. The old answer sent people off to
        // check a credential they had never been asked for.
        if status == 401, lowered.contains("sign in") {
            return .signInRequired(Self.signInToGenerate)
        }
        if lowered.contains("voice_limit") || lowered.contains("voice limit")
            || lowered.contains("maximum amount of custom voices") {
            return .voiceLimitReached
        }

        if kind == .speech,
           lowered.contains("invalid id") || lowered.contains("voice_not_found")
            || lowered.contains("voice not found") {
            return .voiceUnavailable(detail)
        }

        switch status {
        case 401, 403:
            return .unauthorised
        case 404:
            return kind == .speech
                ? .voiceUnavailable(detail)
                : .provider(status: 404, detail: detail)
        case 429:
            return .rateLimited
        case 400, 422:
            // A genuine bad voice id is caught by the string check above. What
            // reaches here on a speech call is a bad model id, malformed text
            // or a bad output format — none of which are fixed by creating a
            // new voice, so do not offer that as the remedy.
            return kind == .speech
                ? .provider(status: status, detail: detail)
                : .sampleRejected(detail)
        default:
            return .provider(status: status, detail: detail)
        }
    }

    /// `detail` arrives as a dictionary, a plain string, or — from FastAPI
    /// validation errors, which is what ElevenLabs runs — an array of objects.
    private func extractDetail(_ body: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: body) else {
            return String(data: body.prefix(200), encoding: .utf8) ?? ""
        }
        if let dict = object as? [String: Any] {
            if let d = dict["detail"] as? [String: Any] {
                return (d["message"] as? String) ?? (d["status"] as? String) ?? ""
            }
            if let d = dict["detail"] as? String { return d }
            if let list = dict["detail"] as? [[String: Any]] {
                return list.compactMap { $0["msg"] as? String }.joined(separator: "; ")
            }
            if let message = dict["message"] as? String { return message }
        }
        return ""
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "mp3":         return "audio/mpeg"
        case "m4a", "mp4":  return "audio/mp4"
        case "wav":         return "audio/wav"
        case "aac":         return "audio/aac"
        case "caf":         return "audio/x-caf"
        default:            return "application/octet-stream"
        }
    }
}
