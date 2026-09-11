import Foundation

protocol Transcriber {
    func transcribe(fileURL: URL) async throws -> String
}

enum TranscriptionError: LocalizedError, Equatable {
    case notConfigured
    case tooQuiet
    case rateLimited
    case unknownModel(String)
    case provider(status: Int, message: String?)
    case badResponse
    case offline

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return L("Speaking into the app is not set up on this build.")
        case .tooQuiet:
            return L("Nothing was heard. Hold the phone closer and try again.")
        case .rateLimited:
            return L("The transcription service is busy. Wait a few seconds and try again.")
        case .unknownModel(let id):
            return L("That model is not available on this key.") + " (\(id))"
        case .provider(let status, let message):
            if let message, !message.isEmpty {
                return L("That could not be written down. Try again.") + " " + message
            }
            return L("That could not be written down. Try again.") + " (\(status))"
        case .badResponse:
            return L("The transcription came back in a shape the app did not understand.")
        case .offline:
            return L("No internet connection.")
        }
    }
}

/// Whisper over the same OpenAI-compatible host as the story questions, so
/// speaking into the app costs no second account and no second key.
///
/// The model matters more than it looks. The first version of this project
/// measured both: `whisper-large-v3-turbo` reached 16.5% median CER on real
/// Emirati dialect across 30 clips, while plain `large-v3` hallucinated
/// "subscribe to the channel" onto near-silent audio at 86% CER. Use turbo.
struct WhisperClient: Transcriber {

    var baseURL: String = AppConfig.llmBaseURL
    var apiKey: String = AppConfig.llmKey
    var model: String = AppConfig.whisperModel

    func transcribe(fileURL: URL) async throws -> String {
        guard !apiKey.isEmpty else { throw TranscriptionError.notConfigured }
        guard let url = URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                            + "/audio/transcriptions") else {
            throw TranscriptionError.notConfigured
        }

        let audio: Data
        do { audio = try Data(contentsOf: fileURL) } catch { throw TranscriptionError.tooQuiet }
        guard audio.count > 4_000 else { throw TranscriptionError.tooQuiet }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = AppConfig.companionTimeout
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)",
                         forHTTPHeaderField: "Content-Type")

        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n"
                        .data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audio)
        body.append("\r\n".data(using: .utf8)!)
        field("model", model)
        field("response_format", "json")
        // `language` is deliberately not sent. The app is bilingual and a
        // forced `ar` mangles English dictation. Note that the 16.5% CER figure
        // above WAS measured with language=ar, so it does not transfer
        // unchanged to this configuration.
        field("temperature", "0")
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost:
                throw TranscriptionError.offline
            default:
                throw TranscriptionError.provider(status: -1, message: error.localizedDescription)
            }
        }

        guard let http = response as? HTTPURLResponse else { throw TranscriptionError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let errorObject = root?["error"] as? [String: Any]
            let message = (errorObject?["message"] as? String)
                ?? String(data: data, encoding: .utf8)
            if (message ?? "").lowercased().contains("model") &&
                (message ?? "").lowercased().contains("not exist") {
                throw TranscriptionError.unknownModel(model)
            }
            if http.statusCode == 429 { throw TranscriptionError.rateLimited }
            throw TranscriptionError.provider(status: http.statusCode, message: message)
        }

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = root["text"] as? String else {
            throw TranscriptionError.badResponse
        }

        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw TranscriptionError.tooQuiet }
        return cleaned
    }
}

#if DEBUG
struct MockTranscriber: Transcriber {
    func transcribe(fileURL: URL) async throws -> String {
        try? await Task.sleep(nanoseconds: 500_000_000)
        return "This is offline test mode, so nothing was really transcribed."
    }
}
#endif
