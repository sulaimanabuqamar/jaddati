import Foundation

/// Produces the WORDS. The voice is the AI capability in this product; this
/// file only decides what gets said.
///
/// It is deliberately local and deterministic:
///   - affirmations come from a fixed bank, so "Comfort me" works offline and
///     costs nothing,
///   - a retelling is ASSEMBLED from sentences the family actually wrote. It
///     never invents biography. If there are no notes, there is no retelling.
///   - fiction is drawn from templates and is always labelled as invented.
///
/// A language model can be dropped in behind `Composer` later without changing
/// any view. What must not change is the rule that a family account may only
/// contain the family's own words.
enum Composer {

    // MARK: Comfort

    struct Affirmation: Identifiable, Hashable {
        let id: String
        let english: String
        let arabic: String
    }

    static let affirmations: [Affirmation] = [
        .init(id: "time",
              english: "Take your time. You don't have to figure everything out today.",
              arabic: "خذي وقتك. ما لازم تفهمين كل شي اليوم."),
        .init(id: "proud",
              english: "I am proud of you. I always was.",
              arabic: "أنا فخورة فيك. وكنت دايماً فخورة فيك."),
        .init(id: "rest",
              english: "Rest, my dear. The work will still be there tomorrow.",
              arabic: "ارتاحي يا عمري. الشغل باقي لين باچر."),
        .init(id: "enough",
              english: "You have done enough today. Come and sit with me.",
              arabic: "كفايه عليك اليوم. تعالي اقعدي عندي."),
        .init(id: "home",
              english: "Wherever you go, you carry this house with you.",
              arabic: "وين ما تروحين، هالبيت معك."),
        .init(id: "afraid",
              english: "It is alright to be afraid. Go slowly, and keep going.",
              arabic: "ما عليه إذا خفتِ. امشي على مهلك، بس لا توقفين.")
    ]

    /// Turns a free-text wish ("I'm nervous about my exam") into words to say.
    /// Matched against the bank rather than generated, so the result is always
    /// something a human wrote and we can stand behind.
    static func comfort(matching wish: String) -> Affirmation {
        let text = wish.lowercased()
        func any(_ words: [String]) -> Bool { words.contains { text.contains($0) } }

        if any(["tired", "exhaust", "sleep", "تعب", "نعسان"]) { return affirmations[2] }
        if any(["proud", "fail", "not good enough", "فخور", "فشل"]) { return affirmations[1] }
        if any(["afraid", "scared", "nervous", "anxious", "خايف", "خوف"]) { return affirmations[5] }
        if any(["busy", "too much", "overwhelm", "زحمة", "ضغط"]) { return affirmations[3] }
        if any(["home", "far", "miss", "بيت", "اشتقت"]) { return affirmations[4] }
        return affirmations[0]
    }

    // MARK: Stories

    /// Retells what the family wrote, in the first person, without adding facts.
    /// Returns nil when there is nothing to retell — the UI then asks for a
    /// memory instead of inventing one.
    static func retelling(from notes: [FamilyNote], personName: String) -> String? {
        let lines = notes
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }

        var out = "Let me tell you something we remember.\n\n"
        for line in lines.prefix(4) {
            let sentence = line.hasSuffix(".") || line.hasSuffix("!") || line.hasSuffix("؟")
                ? line : line + "."
            out += sentence + "\n"
        }
        out += "\nThat is what your family wrote down, in their words."
        return out
    }

    struct Story: Identifiable, Hashable {
        let id: String
        let title: String
        let text: String
    }

    /// Invented bedtime stories. Always labelled as fiction in the UI.
    static let bedtimeStories: [Story] = [
        .init(id: "lamp", title: "The lamp that waited",
              text: "There was a small lamp in the hallway that never went out. It was not a brave lamp, and it was not a bright one. It simply stayed on, so that whoever came home late would not have to find the door in the dark. Sleep now. The lamp is still on."),
        .init(id: "palm", title: "The date palm",
              text: "A girl once planted a date stone and watched it every morning for a week. Nothing happened, so she stopped watching. Years later she came back and stood in its shade. Some things grow whether or not anyone is looking. Sleep now, and let them grow."),
        .init(id: "sea", title: "The sea at night",
              text: "The fishermen used to say the sea is loudest just before it turns calm. When you hear it roaring, that is not the storm arriving. That is the storm leaving. Close your eyes. It is already leaving.")
    ]
}
