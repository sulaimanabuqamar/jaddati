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

    /// Non-personified on purpose. The previous bank said things like "I am
    /// proud of you. I always was." — which is the app asserting what a dead
    /// person felt. These lines steady the listener without claiming anyone's
    /// feelings, wishes, presence, or approval. They are attributed to whoever
    /// chose them, never to the person whose voice reads them.
    /// What to ask for, while they are still here to give it.
    ///
    /// Most families discover too late that they have nothing usable — a few
    /// seconds of somebody laughing behind a video, and that is all. The hard
    /// part is not the recording, it is knowing what to ask for, so these ask
    /// for specific things rather than "a voice sample".
    ///
    /// Each is worth having for its own sake, and together they cover the range
    /// a clone needs: ordinary speech, names said the way they are always said,
    /// warmth, and length.
    static let capturePrompts: [CapturePrompt] = [
        .init(id: "names",
              english: "Say the name of everyone in the family, one by one, the way you always say them.",
              arabic: "اذكر اسم كل فرد في العائلة، واحدًا واحدًا، بالطريقة التي تناديهم بها دائمًا."),
        .init(id: "meeting",
              english: "Tell the story of how you met — take your time with it.",
              arabic: "احكِ قصة كيف تقابلتما — وخذ وقتك فيها."),
        .init(id: "home",
              english: "Describe the house you grew up in, room by room.",
              arabic: "صف البيت الذي نشأت فيه، غرفة غرفة."),
        .init(id: "recipe",
              english: "Talk me through making the dish you are known for.",
              arabic: "اشرح لي طريقة تحضير الأكلة التي تشتهر بها."),
        .init(id: "advice",
              english: "What would you want said at a wedding, years from now?",
              arabic: "ماذا تودّ أن يُقال في عرس بعد سنوات من الآن؟"),
        .init(id: "bedtime",
              english: "Read a page of anything at all, in your ordinary reading voice.",
              arabic: "اقرأ صفحة من أي شيء، بصوت القراءة المعتاد لديك."),
    ]

    static let affirmations: [Affirmation] = [
        .init(id: "words",
              english: "You do not have to put everything into words.",
              arabic: "ليس عليك أن تعبّر عن كل شيء بالكلمات."),
        .init(id: "quiet",
              english: "One quiet moment is enough for now.",
              arabic: "تكفي الآن لحظة هدوء واحدة."),
        .init(id: "pace",
              english: "There is no right pace for grief.",
              arabic: "لا وتيرة واحدة صحيحة للحزن."),
        .init(id: "pause",
              english: "You can pause. Nothing needs to be decided now.",
              arabic: "يمكنك التمهّل. لا يلزم أن تحسم شيئًا الآن."),
        .init(id: "small",
              english: "Let today be as small as it needs to be.",
              arabic: "اكتفِ اليوم بما تستطيع."),
        .init(id: "breath",
              english: "If it helps, take one slow breath.",
              arabic: "إن كان ذلك يساعدك، خذ نفسًا بطيئًا.")
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
    static func retelling(from notes: [FamilyNote]) -> String? {
        let lines = notes
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }

        // Every note goes in. Quietly keeping the four oldest and then closing
        // with "that is what your family wrote down" would be a false claim, and
        // the ordering meant the newest memories were the ones dropped.
        let terminators: Set<Character> = [".", "!", "?", "؟", "…", ":", "؛"]
        var out = "These are words your family wrote down.\n\n"
        for line in lines {
            let sentence = terminators.contains(line.last ?? " ") ? line : line + "."
            out += sentence + "\n"
        }
        out += "\nThat is what your family wrote down, in their words."
        return out
    }

    struct Story: Identifiable, Hashable {
        let id: String
        let title: String
        let titleArabic: String
        let text: String
        let textArabic: String
    }

    /// Invented bedtime stories, written for this app. Always labelled as
    /// fiction in the UI. Both languages are first-class: the masthead is
    /// جدّتي, so an Arabic listener should not have to settle for a translation
    /// button.
    static let bedtimeStories: [Story] = [
        .init(
            id: "moon",
            title: "The moon\u{2019}s little garden",
            titleArabic: "حديقة القمر الصغيرة",
            text: "High above the rooftops, the moon kept a small garden. Nothing grew there but quiet, and the quiet grew very well. Every night the moon watered it, and every night a little of it drifted down to the sleeping town, settling on windowsills and on the backs of cats and on the eyelids of children who were not quite asleep. If you are still awake, that is only because your share is still on its way. It is coming. It always comes.",
            textArabic: "فوق سطوح البيوت، كان للقمر حديقة صغيرة. لم يكن ينبت فيها سوى الهدوء، وكان الهدوء ينمو فيها نموًا جميلًا. في كل ليلة يسقيها القمر، وفي كل ليلة ينزل شيء منها إلى البلدة النائمة، فيستقرّ على حوافّ النوافذ، وعلى ظهور القطط، وعلى جفون الأطفال الذين لم يناموا بعد. وإن كنت ما زلت مستيقظًا، فذلك لأن نصيبك في الطريق. سيصل. إنه يصل دائمًا."
        ),
        .init(
            id: "lantern",
            title: "The lantern by the sea",
            titleArabic: "الفانوس عند البحر",
            text: "There was a lantern at the end of a stone pier who believed her light was too small to matter. The sea was so wide, and she was only one small flame. But every night the fishing boats turned toward her, and every night they came home. She never learned how far her light reached. That is the way with small lights. They do not get to see the whole distance they travel.",
            textArabic: "كان عند طرف رصيف حجري فانوسٌ يظنّ أن ضوءه أصغر من أن يعني شيئًا. فالبحر واسع، وهو شعلة صغيرة واحدة. لكن قوارب الصيد كانت في كل ليلة تلتفت إليه، وفي كل ليلة تعود إلى بيتها. ولم يعرف الفانوس قط إلى أي مدى يصل ضوءه. هكذا هي الأضواء الصغيرة: لا يُتاح لها أن ترى المسافة التي تقطعها كاملة."
        ),
        .init(
            id: "olive",
            title: "The sleepy olive tree",
            titleArabic: "شجرة الزيتون النعسانة",
            text: "An old olive tree on the hill had been standing for four hundred years and had decided, that evening, to have a rest. The wind came to argue with her, as the wind does. She did not argue back. She simply held still, and held her leaves, and held the small brown bird that had chosen her for the night. In the morning the wind had gone somewhere else, and the bird was still there, and so was she.",
            textArabic: "على التلّة شجرة زيتون عتيقة، واقفة منذ أربعمئة عام، قرّرت في ذلك المساء أن تستريح. جاءت الريح لتجادلها، كعادة الريح. فلم تجادلها الشجرة. اكتفت بأن تثبت، وأن تمسك أوراقها، وأن تحمي ذلك الطائر البنيّ الصغير الذي اختارها لليلته. وفي الصباح كانت الريح قد ذهبت إلى مكان آخر، وكان الطائر ما زال هناك، وكانت هي كذلك."
        )
    ]
}
