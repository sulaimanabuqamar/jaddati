import Foundation

/// Talks to any OpenAI-compatible `/chat/completions` endpoint.
///
/// The host is a setting rather than a rewrite, because that shape is spoken by
/// every free open-weights host worth using — Groq, OpenRouter, Together,
/// Cerebras, and a llama.cpp server on a laptop. If one retires a model or the
/// free tier changes, the fix is two strings in `Secrets.plist`.
struct LLMClient: StoryCompanion {

    var baseURL: String = AppConfig.llmBaseURL
    var apiKey: String = AppConfig.llmKey
    var model: String = AppConfig.llmModel
    var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = AppConfig.companionTimeout
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    func answer(question: String, page: PageContext) async throws -> String {
        guard Consent.networkAllowed else { throw ConsentMissing() }
        guard !apiKey.isEmpty else { throw CompanionError.notConfigured }
        guard let url = URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                            + "/chat/completions") else {
            throw CompanionError.notConfigured
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if AppConfig.sendsTextDeviceHeader {
            request.setValue(AppConfig.deviceId, forHTTPHeaderField: "X-Jaddati-Device")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": Self.systemPrompt(for: page)],
                ["role": "user", "content": String(question.prefix(300))]
            ],
            // Two sentences do not need more than this, and a small ceiling is
            // the cheapest guard against a model that decides to write an essay
            // the app would then pay ElevenLabs to read aloud.
            "max_tokens": 160,
            "temperature": 0.6
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost:
                throw CompanionError.offline
            default:
                throw CompanionError.provider(status: -1, message: error.localizedDescription)
            }
        }

        guard let http = response as? HTTPURLResponse else { throw CompanionError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.mapError(status: http.statusCode, body: data, model: model)
        }

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw CompanionError.badResponse
        }

        let cleaned = Self.tidy(content)
        guard !cleaned.isEmpty else { throw CompanionError.emptyAnswer }
        return cleaned
    }

    // MARK: Prompt

    static func systemPrompt(for page: PageContext) -> String {
        """
        You are helping read a children's storybook aloud. A child has stopped \
        the story to ask a question. Your answer will be spoken out loud, so \
        write only words that sound natural when someone reads them.

        Follow every one of these:
        - One or two short sentences. Never more.
        - Answer in the same language the page below is written in.
        - Warm and simple, pitched at a young child.
        - If the answer is in Arabic, use everyday Gulf wording rather than \
        formal newspaper Arabic - the way a grandmother in the Emirates would \
        explain it at home. This is the one place in the app where the dialect \
        can be steered at all, so it is worth asking for.
        - Stay with the story. If the question is not about the story, answer it \
        in one kind sentence and turn back to the page.
        - Never say or imply that you are a real person, never claim to remember \
        anything, and never talk about yourself.
        - Plain spoken words only. No markdown, no lists, no emoji, no stage \
        directions, and no quotation marks wrapped around the whole answer.

        The book is "\(page.bookTitle)". This is page \(page.pageNumber), and it reads:
        \(page.pageText)
        """
    }

    /// Models leak formatting no matter how firmly the prompt asks them not to,
    /// and every stray asterisk becomes a sound the voice has to make.
    static func tidy(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for marker in ["**", "__", "*", "`", "#"] {
            text = text.replacingOccurrences(of: marker, with: "")
        }
        text = text.replacingOccurrences(of: "\n", with: " ")
        while text.contains("  ") { text = text.replacingOccurrences(of: "  ", with: " ") }
        // A whole answer wrapped in quotes is read aloud as a quotation.
        let quotes: [(Character, Character)] = [("\"", "\""), ("\u{201C}", "\u{201D}")]
        for (open, close) in quotes where text.first == open && text.last == close && text.count > 2 {
            text = String(text.dropFirst().dropLast())
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Errors

    static func mapError(status: Int, body: Data, model: String) -> CompanionError {
        let root = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let errorObject = root?["error"] as? [String: Any]
        let message = (errorObject?["message"] as? String)
            ?? (root?["message"] as? String)
            ?? String(data: body, encoding: .utf8)
        let code = (errorObject?["code"] as? String) ?? ""
        let haystack = ((message ?? "") + " " + code).lowercased()

        // Checked before the status switch: a retired model id comes back as a
        // plain 400 on some hosts and a 404 on others, and "bad request" tells
        // nobody which of the two strings in Secrets.plist is wrong.
        if haystack.contains("model") &&
            (haystack.contains("not found") || haystack.contains("does not exist")
             || haystack.contains("decommission") || haystack.contains("no longer")) {
            return .unknownModel(model)
        }

        switch status {
        case 401, 403:
            return .provider(status: status, message: L("The key for the question service was refused."))
        case 404:
            return .unknownModel(model)
        case 429:
            return .rateLimited
        default:
            return .provider(status: status, message: message)
        }
    }
}
