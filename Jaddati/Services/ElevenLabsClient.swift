import Foundation

/// Direct client for the two ElevenLabs endpoints this app uses.
///
///   POST /v1/voices/add                 multipart: name, files  -> { voice_id, requires_verification }
///   POST /v1/text-to-speech/{voice_id}  json: { text, model_id } -> mp3 bytes
struct ElevenLabsClient: VoiceService {

    private let base = URL(string: "https://api.elevenlabs.io")!
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

    init(key: String = AppConfig.elevenLabsKey) {
        self.key = key
    }

    // MARK: Voice creation

    func createVoice(name: String, sampleURL: URL) async throws -> CreatedVoice {
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
            // Split deliberately: a single case listing both patterns cannot
            // compile, because `status` is bound by one of them and not the other.
            switch error {
            case .provider(let status, _) where status == 422 || status == 400:
                return try await retryVoice(name: name, data: sampleData, url: sampleURL)
            case .sampleRejected, .badResponse:
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
        let boundary = "jaddati.\(UUID().uuidString)"
        var request = URLRequest(url: base.appendingPathComponent("v1/voices/add"))
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
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

    func synthesize(text: String, voiceId: String, modelId: String) async throws -> Data {
        guard !key.isEmpty else { throw VoiceServiceError.notConfigured }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= AppConfig.maxCharactersPerGeneration else {
            throw VoiceServiceError.textTooLong(limit: AppConfig.maxCharactersPerGeneration)
        }

        var components = URLComponents(
            url: base.appendingPathComponent("v1/text-to-speech/\(voiceId)"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "output_format", value: "mp3_44100_128")]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "text": trimmed,
            "model_id": modelId
        ])

        let (data, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse else { throw VoiceServiceError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw mapError(status: http.statusCode, body: data)
        }
        guard data.count > 500 else { throw VoiceServiceError.badResponse }
        return data
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

    /// Turns a provider status code into something a person can act on.
    ///
    /// Quota and voice-slot exhaustion are checked BEFORE the status switch:
    /// ElevenLabs reports credit exhaustion as 401, and treating that as a bad
    /// key sends you debugging the wrong thing while the judges wait.
    private func mapError(status: Int, body: Data) -> VoiceServiceError {
        let detail = extractDetail(body)
        let lowered = detail.lowercased()

        if lowered.contains("quota") || lowered.contains("credit") || lowered.contains("exceeded") {
            return .outOfCredits
        }
        if lowered.contains("voice_limit") || lowered.contains("voice limit")
            || lowered.contains("maximum amount of custom voices") {
            return .voiceLimitReached
        }

        switch status {
        case 401, 403:
            return .unauthorised
        case 429:
            return .rateLimited
        case 400, 422:
            return .sampleRejected(detail)
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
