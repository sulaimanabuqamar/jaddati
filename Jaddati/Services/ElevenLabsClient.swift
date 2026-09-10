import Foundation

/// Direct client for the two ElevenLabs endpoints this app uses.
///
///   POST /v1/voices/add                 multipart: name, files  -> { voice_id }
///   POST /v1/text-to-speech/{voice_id}  json: { text, model_id } -> mp3 bytes
///
/// Both shapes were read from the current ElevenLabs API reference. Neither has
/// been exercised against a live account from inside the app yet — see
/// docs/verified-vs-unverified.md before claiming otherwise.
struct ElevenLabsClient: VoiceService {

    private let base = URL(string: "https://api.elevenlabs.io")!
    private let key: String
    private let session: URLSession

    init(key: String = AppConfig.elevenLabsKey) {
        self.key = key
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = AppConfig.requestTimeout
        config.timeoutIntervalForResource = AppConfig.requestTimeout * 2
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }

    // MARK: Voice creation

    func createVoice(name: String, sampleURL: URL) async throws -> String {
        guard !key.isEmpty else { throw VoiceServiceError.notConfigured }

        let sampleData: Data
        do { sampleData = try Data(contentsOf: sampleURL) }
        catch { throw VoiceServiceError.badResponse }

        // ~40KB is well under any usable one-minute recording at any sane bitrate.
        guard sampleData.count > 40_000 else { throw VoiceServiceError.sampleTooShort }

        let boundary = "jaddati.\(UUID().uuidString)"
        var request = URLRequest(url: base.appendingPathComponent("/v1/voices/add"))
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
        append("Content-Disposition: form-data; name=\"files\"; filename=\"\(sampleURL.lastPathComponent)\"\r\n")
        append("Content-Type: \(mimeType(for: sampleURL))\r\n\r\n")
        body.append(sampleData)
        append("\r\n--\(boundary)--\r\n")

        request.httpBody = body

        let (data, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse else { throw VoiceServiceError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw mapError(status: http.statusCode, body: data)
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let voiceId = object["voice_id"] as? String, !voiceId.isEmpty else {
            throw VoiceServiceError.badResponse
        }
        return voiceId
    }

    // MARK: Speech

    func synthesize(text: String, voiceId: String, modelId: String) async throws -> Data {
        guard !key.isEmpty else { throw VoiceServiceError.notConfigured }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= AppConfig.maxCharactersPerGeneration else {
            throw VoiceServiceError.textTooLong(limit: AppConfig.maxCharactersPerGeneration)
        }

        var components = URLComponents(
            url: base.appendingPathComponent("/v1/text-to-speech/\(voiceId)"),
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
            return try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .timedOut:                       throw VoiceServiceError.timedOut
            case .notConnectedToInternet,
                 .networkConnectionLost,
                 .cannotFindHost,
                 .dataNotAllowed:                 throw VoiceServiceError.offline
            default:                              throw VoiceServiceError.offline
            }
        }
    }

    /// Turns a provider status code into something a person can act on.
    /// The detail string is read defensively — the exact `detail.status` values
    /// have not been observed live, so we fall back to the raw body.
    private func mapError(status: Int, body: Data) -> VoiceServiceError {
        var detail = ""
        if let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            if let d = object["detail"] as? [String: Any] {
                detail = (d["message"] as? String) ?? (d["status"] as? String) ?? ""
            } else if let d = object["detail"] as? String {
                detail = d
            }
        }
        let lowered = detail.lowercased()

        switch status {
        case 401, 403:
            return .unauthorised
        case 429:
            return lowered.contains("quota") || lowered.contains("credit")
                ? .outOfCredits : .rateLimited
        case 422:
            if lowered.contains("too short") || lowered.contains("duration") {
                return .sampleTooShort
            }
            return .provider(status: status, detail: detail.isEmpty ? "Check the audio file." : detail)
        default:
            if lowered.contains("quota") || lowered.contains("credit") { return .outOfCredits }
            return .provider(status: status, detail: detail)
        }
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
