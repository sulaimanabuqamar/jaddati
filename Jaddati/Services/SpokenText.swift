import Foundation

/// What happens to the words between the box someone types in and the voice
/// that speaks them.
///
/// Three things, and the order matters: refuse before anything is spent, make
/// the Arabic pronounceable, then put the pauses in. All of it lives inside
/// `synthesize` rather than at the call sites, because there are five call
/// sites and the one that gets forgotten is the one a judge will find.
enum SpokenText {

    // MARK: Pauses

    /// ElevenLabs reads `<break>` on the v2 models, which is what this app
    /// uses. Their own guidance caps a break at three seconds and warns that
    /// too many in one generation make the model speed up or add artefacts —
    /// hence the ceiling below rather than a tag between every paragraph of a
    /// long letter.
    static let pause = "<break time=\"0.9s\" />"
    static let maximumPauses = 6

    /// A blank line between two paragraphs becomes a pause. A single newline
    /// does not: that is a line break inside a thought, and pausing there
    /// would chop up an address or a list of names.
    static func withParagraphPauses(_ text: String) -> String {
        let unified = text.replacingOccurrences(of: "\r\n", with: "\n")
        guard unified.range(of: "\n[ \t]*\n", options: .regularExpression) != nil else {
            return unified
        }
        let spaced = unified.replacingOccurrences(
            of: "\n[ \t]*(?:\n[ \t]*)+",
            with: "\n" + pause + "\n",
            options: .regularExpression
        )
        // Past the ceiling, no tags at all. A letter that speeds up and gargles
        // is worse than one read straight through.
        let inserted = spaced.components(separatedBy: pause).count - 1
        return inserted <= maximumPauses ? spaced : unified
    }

    // MARK: Arabic marks

    static let addsHarakat = true

    private static let markRange = 0x064B...0x0652
    private static let letterRange = 0x0620...0x064A

    /// Arabic written bare — no fatha, no damma, nothing. The voice service
    /// then has to guess which word "علم" is, and it guesses wrong often
    /// enough to be worth one call to fix.
    ///
    /// Short strings are left alone: the call costs a question from the
    /// month's allowance and a second of waiting, and "نعم" does not need it.
    static func needsHarakat(_ text: String) -> Bool {
        var letters = 0, marks = 0
        for scalar in text.unicodeScalars {
            let value = Int(scalar.value)
            if letterRange.contains(value) { letters += 1 }
            if markRange.contains(value) || value == 0x0670 { marks += 1 }
        }
        guard letters >= 12 else { return false }
        return Double(marks) / Double(letters) < 0.15
    }

    /// The same text with every mark and tatweel removed, whitespace flattened.
    /// Used to check that the model added marks rather than rewriting the words.
    static func withoutMarks(_ text: String) -> String {
        var out = ""
        for scalar in text.unicodeScalars {
            let value = Int(scalar.value)
            if markRange.contains(value) || value == 0x0670 || value == 0x0640 { continue }
            out.append(Character(scalar))
        }
        return out.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// True when `vowelled` is the same sentence as `original`, only marked.
    ///
    /// This is the whole safety of the feature. A model asked to add harakat
    /// will sometimes helpfully correct the grammar, or answer the sentence
    /// instead of marking it — and that would put words the family never wrote
    /// into a dead person's mouth, which is the one thing this app promises
    /// never to do. If the letters changed at all, the original is used.
    static func marksOnly(_ vowelled: String, matches original: String) -> Bool {
        !vowelled.isEmpty && withoutMarks(vowelled) == withoutMarks(original)
    }
}

/// Adding the marks. A `ChatCalling` conformance like the translator's, so it
/// goes through the same relay, the same consent check and the same timeout.
struct TashkeelService {
    var baseURL: String = AppConfig.llmBaseURL
    var apiKey: String = AppConfig.llmKey
    var model: String = AppConfig.llmModel
    var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = AppConfig.companionTimeout
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    private static let instruction = """
    You add Arabic diacritics (tashkeel/harakat) to text. Return ONLY the same \
    text with full diacritics added. Do not translate. Do not answer it. Do not \
    correct spelling or grammar. Do not add, remove or reorder a single word or \
    letter. Do not add quotation marks or any commentary. If the text is not \
    Arabic, return it exactly as given.
    """

    /// Best effort by design: every failure path returns the original text.
    /// Nobody should lose a generation because a diacritics call timed out.
    func vowelled(_ text: String) async -> String {
        guard SpokenText.addsHarakat, SpokenText.needsHarakat(text) else { return text }
        // keepLines, because the paragraphs in what was typed are the pauses in
        // what is heard, and this call is the only thing standing between them.
        guard let reply = try? await chat(system: Self.instruction, user: text,
                                          maxTokens: 1400, temperature: 0,
                                          keepLines: true) else {
            return text
        }
        // Trimmed at the ends only: a blank line in the MIDDLE is the thing
        // being preserved, and `.whitespacesAndNewlines` at the ends leaves it
        // alone.
        let cleaned = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        return SpokenText.marksOnly(cleaned, matches: text) ? cleaned : text
    }
}

extension TashkeelService: ChatCalling {}
