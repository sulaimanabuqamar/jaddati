import Foundation

/// Raised when the family's notes do not answer the question.
///
/// This is a designed outcome, not a fault. It is the whole reason the feature
/// is safe to ship: a model asked about a dead grandmother and allowed to fill
/// a gap will produce a favourite dish, a birthplace, a saying — warmly, in her
/// voice, and the family will believe it. So the gap is reported instead.
struct NotInNotes: LocalizedError {
    var errorDescription: String? {
        L("That is not in the memories your family has written down. Add it under Words & memories and ask again.")
    }
}

/// An answer assembled ONLY from what the family wrote down.
///
/// Like the book companion, this is never told whose voice will read the answer
/// out. The rule has not changed and neither has the reason: a model told it is
/// speaking as someone's grandmother starts claiming memories she never had.
/// What it gets here is the family's own notes, as material, with an explicit
/// instruction not to speak as her and not to go outside them.
struct FamilyAnswerService {

    var baseURL: String = AppConfig.llmBaseURL
    var apiKey: String = AppConfig.llmKey
    var model: String = AppConfig.llmModel
    var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = AppConfig.companionTimeout
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    /// The exact token the model is told to return when the notes fall short.
    static let notInNotesToken = "NOT_IN_NOTES"

    func answer(question: String, notes: [FamilyNote]) async throws -> String {
        let material = notes
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // No notes at all means there is nothing to ground an answer in, so the
        // model is never asked. Asked to answer from nothing, it answers from
        // everything it has ever read.
        guard !material.isEmpty else { throw NotInNotes() }

        let answer = try await chat(system: Self.systemPrompt(notes: material),
                                    // The compose box offers 600 and the clip
                                    // records all 600 as "You asked:", so
                                    // cutting to 300 half-asked the question
                                    // and filed the answer against wording the
                                    // model never saw.
                                    user: String(question.prefix(600)),
                                    maxTokens: 160, temperature: 0.2)
        // Letters only: models routinely normalise the underscores out of a
        // token they were shown inline in prose, and "NOT IN NOTES" returned as
        // an answer would be billed, captioned "From your family's notes" and
        // read aloud in her voice. The refusal is the feature.
        // Latin letters only, by instruction above — but a model told to answer
        // in the question's language will sometimes refuse in Arabic anyway, and
        // a scan for a Latin token cannot see that. So the shape of the reply is
        // checked too: a refusal is short and says it does not know, and a real
        // answer drawn from notes is neither.
        let bare = answer.uppercased().filter { $0.isLetter }
        if bare.contains("NOTINNOTES") { throw NotInNotes() }
        if Self.readsAsRefusal(answer) { throw NotInNotes() }
        return answer
    }

    /// A refusal the model wrote in its own words rather than as the token.
    ///
    /// Deliberately narrow: it must be short AND contain one of these. A long
    /// answer that happens to mention "لا أعرف" in passing is a real answer.
    static func readsAsRefusal(_ answer: String) -> Bool {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 120 else { return false }
        let phrases = [
            "لا أعرف", "لا اعرف", "غير مذكور", "غير موجود", "لا يوجد",
            "ليس في الملاحظات", "لا تذكر الملاحظات", "لم يُذكر", "لم يذكر",
            "i don't know", "i do not know", "not in the notes", "not mentioned",
            "no information", "the notes do not",
        ]
        let lowered = trimmed.lowercased()
        return phrases.contains { lowered.contains($0) }
    }

    static func systemPrompt(notes: [String]) -> String {
        let numbered = notes.enumerated()
            .map { "[\($0.offset + 1)] \($0.element)" }
            .joined(separator: "\n")
        return """
        You are given a set of notes a family wrote down about someone who has died. \
        Answer the question using ONLY the information in those notes.

        Rules, all of them:
        - If the notes do not contain the answer, reply with exactly \
        \(notInNotesToken) and nothing else. Write that token in Latin letters \
        even when answering in Arabic — it is a signal to the app, not to a \
        reader, and it is the ONLY case where you do not answer in the \
        question's language.
        - Never guess, never generalise from what is typical, never fill a gap.
        - Do not speak as the person. Do not say "I". Do not claim to remember anything.
        - One or two short sentences. It will be read out loud, so write words that \
        sound natural spoken.
        - Answer in the same language the question is written in.
        - If the answer is in Arabic, use everyday Gulf wording rather than formal \
        newspaper Arabic.
        - Plain words only: no markdown, no lists, no emoji, and no quotation marks \
        wrapped around the whole answer.

        The notes:
        \(numbered)
        """
    }
}

/// Carrying words across the language a family stopped sharing.
///
/// A translation and nothing more. It does not try to guess how she would have
/// phrased it, because that is invention wearing her voice — the clip says as
/// much, in `Intent.bridgeLanguage.provenanceNote`.
struct TranslatorService {

    var baseURL: String = AppConfig.llmBaseURL
    var apiKey: String = AppConfig.llmKey
    var model: String = AppConfig.llmModel
    var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = AppConfig.companionTimeout
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    enum Target { case arabic, english }

    /// Whichever language the text is NOT.
    static func target(for text: String) -> Target {
        text.unicodeScalars.contains { (0x0600...0x06FF).contains(Int($0.value)) }
            ? .english : .arabic
    }

    func translate(_ text: String, to target: Target? = nil) async throws -> String {
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return "" }
        let to = target ?? Self.target(for: source)

        let system: String
        switch to {
        case .arabic:
            system = """
            Translate the text into Arabic. Use everyday spoken Gulf wording, the way \
            a grandmother in the Emirates would say it at home, rather than formal \
            newspaper Arabic. Return only the translation. No transliteration, no \
            explanation, no quotation marks.
            """
        case .english:
            system = """
            Translate the text into English. Use plain, warm, spoken English — the way \
            it would be said aloud to a child, not written formally. Return only the \
            translation. No explanation, no quotation marks.
            """
        }
        // Roughly a token per two characters, doubled for Arabic's poorer
        // tokenisation, with a floor so a short line is never clipped.
        let budget = max(400, min(1200, source.count))
        return try await chat(system: system, user: String(source.prefix(900)),
                              maxTokens: budget, temperature: 0.2)
    }
}

// MARK: - Shared request

/// Both services talk to the same OpenAI-shaped endpoint the book companion
/// uses, so the transport, the consent gate and the error mapping are written
/// once here rather than three times and left to drift apart.
protocol ChatCalling {
    var baseURL: String { get }
    var apiKey: String { get }
    var model: String { get }
    var session: URLSession { get }
}

extension FamilyAnswerService: ChatCalling {}
extension TranslatorService: ChatCalling {}

extension ChatCalling {
    func chat(system: String, user: String,
              maxTokens: Int, temperature: Double,
              keepLines: Bool = false) async throws -> String {
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
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
            "max_tokens": maxTokens,
            "temperature": temperature,
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
            throw LLMClient.mapError(status: http.statusCode, body: data, model: model)
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw CompanionError.badResponse
        }
        // A reply cut off at the token ceiling is half a sentence. Left
        // unchecked it went straight to the voice service, was billed, and was
        // stored as the clip — Arabic tokenises poorly enough that a long
        // translation reaches the ceiling in ordinary use.
        if (first["finish_reason"] as? String) == "length" {
            throw CompanionError.badResponse
        }

        let cleaned = LLMClient.tidy(content, keepLines: keepLines)
        guard !cleaned.isEmpty else { throw CompanionError.emptyAnswer }
        return cleaned
    }
}
