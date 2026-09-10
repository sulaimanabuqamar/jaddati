import Foundation
import PDFKit

/// Turns a file the user brought in into pages that can be read aloud.
///
/// Nothing is bundled with the app — every word comes from a document the user
/// chose. Whether they hold the rights to have it read aloud is their call, and
/// the import screen says so.
enum BookImporter {

    /// Roughly forty seconds of speech, and roughly 900 credits. Small enough
    /// that a mistake costs little, large enough to feel like a page.
    static let targetPageLength = 900
    /// Never split so tightly that a page is a fragment.
    static let minimumPageLength = 300

    enum ImportError: LocalizedError {
        case unreadable
        case empty
        case tooLarge(characters: Int)

        var errorDescription: String? {
            switch self {
            case .unreadable:
                return "That file could not be read as text. Plain text works best; a scanned PDF has no text in it to read."
            case .empty:
                return "There was no text in that file."
            case .tooLarge(let characters):
                return "That file holds about \(characters / 1000)k characters, which is more than this app will take. Import a chapter rather than a whole book."
            }
        }
    }

    /// Hard stop. Well beyond any plan's credits, so an accidental import of
    /// something enormous fails fast instead of filling storage.
    static let maximumCharacters = 400_000

    static func makeBook(from url: URL, personId: UUID) throws -> Book {
        let raw = try extractText(from: url)
        let cleaned = tidy(raw)
        guard !cleaned.isEmpty else { throw ImportError.empty }
        guard cleaned.count <= maximumCharacters else {
            throw ImportError.tooLarge(characters: cleaned.count)
        }
        let pages = paginate(cleaned)
        guard !pages.isEmpty else { throw ImportError.empty }
        return Book(personId: personId,
                    title: url.deletingPathExtension().lastPathComponent,
                    pages: pages)
    }

    // MARK: Extraction

    static func extractText(from url: URL) throws -> String {
        switch url.pathExtension.lowercased() {
        case "pdf":
            guard let document = PDFDocument(url: url) else { throw ImportError.unreadable }
            var out = ""
            for index in 0..<document.pageCount {
                if let page = document.page(at: index), let text = page.string {
                    out += text + "\n"
                }
            }
            guard !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ImportError.unreadable
            }
            return out
        default:
            // Try UTF-8, then fall back to whatever encoding the file declares.
            if let text = try? String(contentsOf: url, encoding: .utf8) { return text }
            if let text = try? String(contentsOf: url) { return text }
            throw ImportError.unreadable
        }
    }

    /// Collapses the line-wrapping that makes extracted text read badly aloud,
    /// while keeping real paragraph breaks.
    static func tidy(_ input: String) -> String {
        var text = input.replacingOccurrences(of: "\r\n", with: "\n")
        text = text.replacingOccurrences(of: "\u{00AD}", with: "")     // soft hyphen
        // A single newline inside a paragraph becomes a space; two or more stay.
        text = text.replacingOccurrences(of: "(?<!\n)\n(?!\n)",
                                         with: " ",
                                         options: .regularExpression)
        text = text.replacingOccurrences(of: "[ \t]+",
                                         with: " ",
                                         options: .regularExpression)
        text = text.replacingOccurrences(of: "\n{3,}",
                                         with: "\n\n",
                                         options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Pagination

    /// Splits at sentence ends so a page never stops mid-thought. Arabic
    /// terminators are included — this app is read in both scripts.
    static func paginate(_ text: String,
                         target: Int = targetPageLength,
                         minimum: Int = minimumPageLength) -> [String] {
        let sentences = splitIntoSentences(text)
        var pages: [String] = []
        var current = ""

        for sentence in sentences {
            if current.isEmpty {
                current = sentence
            } else if current.count + 1 + sentence.count <= target {
                current += " " + sentence
            } else if current.count < minimum {
                // Too short to stand alone; take the sentence and start fresh.
                current += " " + sentence
                pages.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
            } else {
                pages.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = sentence
            }
        }
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pages.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return pages.filter { !$0.isEmpty }
    }

    /// A sentence longer than a page is broken on whitespace rather than left
    /// to overflow — otherwise one runaway paragraph becomes an unaffordable page.
    static func splitIntoSentences(_ text: String) -> [String] {
        let terminators: Set<Character> = [".", "!", "?", "؟", "۔", "\n"]
        var sentences: [String] = []
        var buffer = ""

        for character in text {
            buffer.append(character)
            if terminators.contains(character) {
                let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { sentences.append(trimmed) }
                buffer = ""
            }
        }
        let tail = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { sentences.append(tail) }

        return sentences.flatMap { sentence -> [String] in
            sentence.count <= targetPageLength ? [sentence] : hardWrap(sentence)
        }
    }

    private static func hardWrap(_ sentence: String) -> [String] {
        var chunks: [String] = []
        var current = ""
        for word in sentence.split(separator: " ") {
            if current.isEmpty {
                current = String(word)
            } else if current.count + 1 + word.count <= targetPageLength {
                current += " " + word
            } else {
                chunks.append(current)
                current = String(word)
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}
