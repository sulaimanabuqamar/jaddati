import Foundation

/// The page a question was asked about. Deliberately small: the companion is
/// given the story in front of the child and nothing else.
///
/// It is NOT given the name or the relationship of the person whose voice will
/// read the answer out. That omission is the design, not an oversight — the
/// voice carries the identity, and a model told whose voice it is will start
/// claiming memories that person never had.
struct PageContext {
    let bookTitle: String
    let pageText: String
    let pageNumber: Int
}

/// A short, spoken-aloud answer to a child's question about the page in front
/// of them. Narrow on purpose: this is not a chat interface.
protocol StoryCompanion {
    func answer(question: String, page: PageContext) async throws -> String
}

enum CompanionError: LocalizedError, Equatable {
    case notConfigured
    case rateLimited
    case unknownModel(String)
    case provider(status: Int, message: String?)
    case badResponse
    case emptyAnswer
    case offline

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Questions aren't set up on this build."
        case .rateLimited:
            return "The question service is busy right now. Wait a few seconds and ask again."
        case .unknownModel(let id):
            return "The model \"\(id)\" isn't available on this key. Run spike/llm_spike.sh to see which ones are."
        case .provider(let status, let message):
            if let message, !message.isEmpty { return "The question service said: \(message)" }
            return "The question service returned an error (\(status))."
        case .badResponse:
            return "The question service replied in a shape the app didn't understand."
        case .emptyAnswer:
            return "No answer came back. Try asking it a different way."
        case .offline:
            return "No internet connection."
        }
    }
}
