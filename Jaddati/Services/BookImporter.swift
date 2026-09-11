import Foundation
import PDFKit

/// Turns a file the user brought in into pages that can be read aloud.
///
/// Nothing is bundled with the app — every word comes from a document the user
/// chose. Whether they hold the rights to have it read aloud is their call, and
/// the import screen says so.
enum BookImporter {

    /// Used only for plain text, and as the point at which one very long PDF
    /// page is split further. Roughly forty seconds of speech, ~900 credits.
    static let targetPageLength = 900
    static let minimumPageLength = 300

    /// Hard stop, well beyond any plan's credits, so an accidental import of
    /// something enormous fails fast instead of filling storage.
    static let maximumCharacters = 400_000

    enum ImportError: LocalizedError {
        case unreadable
        case empty
        case tooLarge(characters: Int)

        var errorDescription: String? {
            switch self {
            case .unreadable:
                return L("That file could not be read as text. Plain text works best; a scanned PDF has no text in it to read.")
            case .empty:
                return L("There was no text in that file.")
            case .tooLarge(let characters):
                return L("That file is larger than this app will take. Import a chapter rather than a whole book.")
                    + " (\(characters / 1000)k)"
            }
        }
    }

    /// `displayName` is passed separately because the file being read may be a
    /// temporary copy with a generated name. Deriving the title from the file
    /// on disk produced book titles that were raw UUIDs.
    static func makeBook(from url: URL, personId: UUID, displayName: String) throws -> Book {
        let pages: [String]
        if url.pathExtension.lowercased() == "pdf" {
            pages = try pdfPages(from: url)
        } else {
            let cleaned = tidy(try plainText(from: url))
            guard !cleaned.isEmpty else { throw ImportError.empty }
            guard cleaned.count <= maximumCharacters else {
                throw ImportError.tooLarge(characters: cleaned.count)
            }
            pages = paginate(cleaned)
        }

        guard !pages.isEmpty else { throw ImportError.empty }
        let total = pages.reduce(0) { $0 + $1.count }
        guard total <= maximumCharacters else { throw ImportError.tooLarge(characters: total) }

        return Book(personId: personId, title: tidyTitle(displayName), pages: pages)
    }

    // MARK: Titles

    /// Filenames arrive with export prefixes and separators that read badly as
    /// a book title — "1789055592043_Zac the Rat" should not be the title.
    static func tidyTitle(_ raw: String) -> String {
        var name = raw
        name = name.replacingOccurrences(of: "^[0-9]{6,}[ _-]+",
                                         with: "",
                                         options: .regularExpression)
        name = name.replacingOccurrences(of: "[_]+", with: " ")
        name = name.replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Untitled" : name
    }

    // MARK: Extraction

    /// A PDF's own pages ARE its pages. Re-flowing them by character count
    /// turned a seven-page picture book into a single block of text.
    /// A page is split further only when it is longer than one spoken page.
    static func pdfPages(from url: URL) throws -> [String] {
        guard let document = PDFDocument(url: url) else { throw ImportError.unreadable }
        var pages: [String] = []

        for index in 0..<document.pageCount {
            guard let raw = document.page(at: index)?.string else { continue }
            let cleaned = tidy(stripPageFurniture(raw))
            guard !cleaned.isEmpty else { continue }        // illustration-only page
            if cleaned.count > targetPageLength {
                pages.append(contentsOf: paginate(cleaned))
            } else {
                pages.append(cleaned)
            }
        }

        guard !pages.isEmpty else { throw ImportError.unreadable }
        return pages
    }

    static func plainText(from url: URL) throws -> String {
        if let text = try? String(contentsOf: url, encoding: .utf8) { return text }
        guard let data = try? Data(contentsOf: url) else { throw ImportError.unreadable }
        for encoding in [String.Encoding.utf16, .isoLatin1, .windowsCP1252, .utf8] {
            if let text = String(data: data, encoding: encoding) { return text }
        }
        throw ImportError.unreadable
    }

    /// Removes the bare page numbers and running heads that sit in a PDF's text
    /// layer. Left in, they are read aloud as words.
    static func stripPageFurniture(_ input: String) -> String {
        input
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { return true }
                // A line that is only digits, or digits with punctuation.
                return !trimmed.allSatisfy { $0.isNumber || $0.isPunctuation || $0.isWhitespace }
            }
            .joined(separator: "\n")
    }

    /// Collapses the line-wrapping that makes extracted text read badly aloud,
    /// while keeping real paragraph breaks.
    static func tidy(_ input: String) -> String {
        var text = input.replacingOccurrences(of: "\r\n", with: "\n")
        text = text.replacingOccurrences(of: "\u{00AD}", with: "")     // soft hyphen
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

    // MARK: Pagination (plain text, and over-long PDF pages)

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
