#if DEBUG
import Foundation

/// Offline test mode's stand-in. It never reaches a network and it never
/// pretends to be clever — it echoes the question back so the flow can be
/// walked through with no key and no spend.
struct MockStoryCompanion: StoryCompanion {
    func answer(question: String, page: PageContext) async throws -> String {
        try? await Task.sleep(nanoseconds: 600_000_000)
        if question.lowercased().contains("fail") { throw CompanionError.rateLimited }
        return "That is a good question about page \(page.pageNumber). "
             + "This is offline test mode, so nothing real was asked."
    }
}
#endif
