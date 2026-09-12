import SwiftUI
import AVFoundation

/// Decide the words, then hear them. One screen per intent, one primary action.
struct CreateView: View {
    let personId: UUID

    /// State rather than a constant, so the strip of other ways to ask can
    /// switch this screen in place. On the web the equivalent replaces the
    /// screen in the stack; here changing the state rebuilds the same one,
    /// which means Back still means "out of here" rather than "the last thing
    /// I tried" — the same outcome by the means this platform gives.
    @State private var intent: Intent

    init(personId: UUID, intent: Intent) {
        self.personId = personId
        _intent = State(initialValue: intent)
    }

    @EnvironmentObject private var library: Library
    /// Same reason as PersonView: the availability flags depend on consent,
    /// and consent publishes nothing of its own.
    @EnvironmentObject private var consent: Consent

    @State private var text: String = ""
    @State private var isGenerating = false
    @State private var errorText: String?
    /// False when the audio WAS created and only the write to disk failed.
    /// Retrying then pays the provider a second time for a clip we already
    /// made, so that message arrives with no Try again button.
    @State private var errorAllowsRetry = true
    /// Kept alongside the message because some failures have a fix the user can
    /// tap. A message telling someone to "add their voice again" on a screen
    /// with no way to do that is a dead end.
    @State private var failure: VoiceServiceError?
    @State private var addingVoice = false
    @State private var generated: AudioAsset?
    @State private var useFastModel = false
    @State private var showingTuning = false
    /// Edited locally and committed when the drag ends. Binding a slider
    /// straight at the library would rewrite the whole index on every tick.
    @State private var draftTuning: VoiceTuning = .natural
    @State private var pendingLineDeletion: FamilyNote?

    private var person: Person? { library.person(withId: personId) }

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Only one failure has a fix the user can perform from this screen.
    private var isRecoverableByRecreatingVoice: Bool {
        if case .some(.voiceUnavailable) = failure { return true }
        return false
    }

    /// The screen-level hint. On the retelling screen it must not promise the
    /// family's words when the family has not written any.
    private var screenNote: String? { intent.provenanceNote }

    /// Why the button is greyed out. Shown under it, because a disabled control
    /// that gives no reason reads as broken.
    private var disabledReason: String? {
        if isGenerating || canSpeak { return nil }
        if !AppConfig.isConfigured { return nil }        // has its own error note above
        if person?.voiceIsUnavailableHere == true {
            return L("The test voice is not a real voice. Create one to continue.")
        }
        if person?.hasVoice != true { return L("Add a voice before creating audio.") }
        if trimmed.count > intent.characterLimit {
            return L("Shorten the text to fit the limit.")
        }
        switch intent {
        case .comfort:
            return L("Choose a line, or write what feels right to you.")
        case .storyFiction:
            return L("Choose a story, or write your own.")
        case .askAboutThem:
            return L("Ask a question about them.")
        case .bridgeLanguage:
            return L("Write something to carry across.")
        case .saySomething, .storyFromMemories, .readBook:
            return L("Type something for them to say.")
        }
    }

    private var canSpeak: Bool {
        !trimmed.isEmpty
            && trimmed.count <= intent.characterLimit
            && !isGenerating
            && person?.hasVoice == true
            && AppConfig.isConfigured
            && !library.loadFailed
    }

    /// The other ways of asking.
    ///
    /// These were six full-width rows on the person screen, each with a title
    /// and a sentence under it, and you had to read all of them to find the
    /// one you wanted. They belong here: the box is the thing, and these are
    /// the other ways to fill it. Reading a book is not one of them — a shelf
    /// is not a compose box — so it stays a door on the person screen.
    private var ways: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(Intent.allCases.filter { $0 != .readBook }, id: \.self) { key in
                    let on = key == intent
                    Button {
                        guard !on else { return }
                        intent = key
                        // A fresh way of asking starts from a fresh box, the
                        // way it does when this screen is entered anew.
                        text = ""
                        errorText = nil
                        generated = nil
                    } label: {
                        Text(key.title)
                            .font(.system(size: 13, weight: on ? .semibold : .medium))
                            .foregroundStyle(on ? Theme.Palette.paper : Theme.Palette.inkSoft)
                            .lineLimit(1)
                            .padding(.horizontal, 14)
                            .frame(minHeight: Theme.Metric.touchTarget)
                            .background(Capsule().fill(on ? Theme.Palette.wine : Theme.Palette.sunk))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, Theme.Metric.screenPadding)
        }
        .padding(.horizontal, -Theme.Metric.screenPadding)
    }

    var body: some View {
        VStack(spacing: 0) {
            // The bar used to name the intent, which the selected chip below
            // it and the headline below that both already said. Three ways of
            // saying one thing pushed the box the user came for most of the
            // way down the screen, so the bar names WHO and the breadcrumb
            // that repeated it is gone.
            AppBar(title: person?.name ?? intent.title)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    // Grouped so the header counts as one child: this stack sits
                    // right on SwiftUI's ten-child ViewBuilder limit.
                    Group {
                        ways
                        Headline(text: intent.headline)
                        SubText(text: intent.standfirst)
                    }

                    if !AppConfig.isConfigured {
                        ErrorNote(message: AppConfig.unavailableMessage)
                    }

                    // On the shelf screen the kept items are the reason you
                    // came, so they sit above the compose box rather than under
                    // everything else.
                    if intent == .storyFromMemories { savedFromHere }

                    switch intent {
                    case .comfort:      comfortPicker
                    case .storyFiction: fictionPicker
                    default:            EmptyView()
                    }

                    editor

                    if let note = screenNote {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 11))
                            Text(note)
                                .font(Theme.Font.caption)
                        }
                        .foregroundStyle(Theme.Palette.bronze)
                    }

                    ExampleQuote(characters: trimmed.count)
                    actionSection
                    if intent != .storyFromMemories { savedFromHere }
                }
                .padding(.horizontal, Theme.Metric.screenPadding)
                .padding(.bottom, Theme.Space.xl)
            }
            // Swiping the page down puts the keyboard away, so the primary
            // action is reachable without hunting for a Done button.
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Theme.Palette.paper)
        .navigationBarHidden(true)
        .navigationDestination(item: $generated) { asset in
            PlayerView(asset: asset)
        }
        .sheet(isPresented: $addingVoice) {
            AddVoiceView(personId: personId)
        }
        .confirmationDialog(L("Remove this line?"),
                            isPresented: Binding(get: { pendingLineDeletion != nil },
                                                 set: { if !$0 { pendingLineDeletion = nil } }),
                            titleVisibility: .visible) {
            Button(L("Remove line"), role: .destructive) {
                if let line = pendingLineDeletion { library.removeNote(line) }
                pendingLineDeletion = nil
            }
            Button(L("Cancel"), role: .cancel) { pendingLineDeletion = nil }
        }
        .onChange(of: person?.voiceId) { _, _ in
            // A new voice invalidates the old complaint.
            errorText = nil
            failure = nil
        }
        .onAppear(perform: seedIfNeeded)
    }

    /// Error, primary action, why-it-is-disabled, progress, model toggle.
    @ViewBuilder private var actionSection: some View {
        if let errorText {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                if errorAllowsRetry {
                    ErrorNote(message: errorText) {
                        self.errorText = nil
                        self.failure = nil
                        Task { await speak() }
                    }
                } else {
                    ErrorNote(message: errorText)
                }
                if isRecoverableByRecreatingVoice {
                    Button(L("Re-create voice")) { addingVoice = true }
                        .buttonStyle(QuietButtonStyle())
                }
            }
        }

        Button(isGenerating ? L("Creating audio…") : L("Create audio")) {
            Task { await speak() }
        }
        .buttonStyle(PrimaryButtonStyle(enabled: canSpeak))
        .disabled(!canSpeak)

        if intent == .comfort, let person, !trimmed.isEmpty, !isAlreadySaved(trimmed, for: person) {
            Button(L("Save this line")) {
                library.add(FamilyNote(personId: person.id,
                                       text: trimmed,
                                       kind: FamilyNote.affirmationKind))
            }
            .buttonStyle(QuietButtonStyle())
        }

        // The same affordance for memories, which nothing else in the app
        // offered. "Ask about them" draws ONLY on these, so with no way to
        // write one down that feature could only ever refuse — and its refusal
        // pointed the reader at this screen.
        if intent == .storyFromMemories, let person, !trimmed.isEmpty,
           !library.memories(for: person).contains(where: { $0.text == trimmed }) {
            Button(L("Keep this as a memory")) {
                library.add(FamilyNote(personId: person.id, text: trimmed))
                text = ""
            }
            .buttonStyle(QuietButtonStyle())
        }

        if let reason = disabledReason {
            Text(reason)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
                .frame(maxWidth: .infinity, alignment: .center)
                .fixedSize(horizontal: false, vertical: true)
        }

        if isGenerating {
            HStack(spacing: 8) {
                ProgressView()
                Text(L("The words are still here."))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
        }

        Toggle(L("Faster, slightly plainer voice"), isOn: $useFastModel)
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Palette.inkSoft)
            .tint(Theme.Palette.bronze)
            .padding(.top, Theme.Space.xs)

        tuningSection
    }

    /// The only fine-tuning an instant clone actually has. The clone itself is
    /// fixed once created; what can be changed is how it performs — how steady
    /// it stays, and how hard it is pushed towards the original recording.
    @ViewBuilder private var tuningSection: some View {
        DisclosureGroup(isExpanded: $showingTuning) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionLabel(text: L("How it is spoken"))
                HStack(spacing: Theme.Space.xs) {
                    tuningPreset(L("Gentle"), .gentle)
                    tuningPreset(L("Natural"), .natural)
                    tuningPreset(L("Storytelling"), .storytelling)
                }

                slider(L("Steadiness"),
                       help: L("More expressive") + " \u{2194} " + L("More steady"),
                       value: $draftTuning.stability)

                slider(L("Likeness to the original"),
                       help: L("Source quality and language both affect the result. A high likeness value is not a guarantee."),
                       value: $draftTuning.similarity)

                paceSlider

                Text(L("Results may differ from the original recording."))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
            .padding(.top, Theme.Space.xs)
        } label: {
            HStack {
                Text(L("Voice delivery"))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
                if let name = draftTuning.presetName {
                    Text(name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.Palette.bronze)
                }
            }
        }
        .tint(Theme.Palette.wineInk)
    }

    private func tuningPreset(_ name: String, _ value: VoiceTuning) -> some View {
        Button {
            draftTuning = value
            commitTuning()
        } label: {
            Text(name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(draftTuning == value ? Theme.Palette.ivory : Theme.Palette.wineInk)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(draftTuning == value ? Theme.Palette.forest : Theme.Palette.ivorySunk)
                )
        }
        .buttonStyle(.plain)
    }

    private func slider(_ title: String, help: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.ink)
                Spacer()
                Text("\(Int((value.wrappedValue * 100).rounded()))%")
                    .font(Theme.Font.caption.monospacedDigit())
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
            Slider(value: value, in: 0...1) { editing in
                if !editing { commitTuning() }      // save on release, not per tick
            }
            .tint(Theme.Palette.bronze)
            .accessibilityLabel(title)
            .accessibilityValue("\(Int((value.wrappedValue * 100).rounded())) percent")
            Text(help)
                .font(.system(size: 11))
                .foregroundStyle(Theme.Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Pace is the one setting that is not a 0-1 dial. The provider accepts
    /// 0.7-1.2, where lower is slower, so it gets its own control rather than
    /// being squeezed into `slider(_:help:value:)`.
    private var paceSlider: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(L("Pace"))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.ink)
                Spacer()
                Text(String(format: "%.2f\u{00D7}", draftTuning.speed))
                    .font(Theme.Font.caption.monospacedDigit())
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
            Slider(value: $draftTuning.speed, in: 0.70...1.20, step: 0.01) { editing in
                if !editing { commitTuning() }      // save on release, not per tick
            }
            .tint(Theme.Palette.bronze)
            .accessibilityLabel(L("Pace"))
            .accessibilityValue(String(format: "%.2f", draftTuning.speed))
            Text(L("Slower") + " \u{2194} " + L("Faster"))
                .font(.system(size: 11))
                .foregroundStyle(Theme.Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Deliberately does nothing now.
    ///
    /// This used to write `draftTuning` onto the person on every slider release
    /// and every preset tap, from a collapsed disclosure on a compose screen.
    /// Tapping Storytelling while browsing stories permanently changed how the
    /// book reader sounded too, with no way back. The draft is passed straight
    /// to `synthesize` instead, and only a generation the user actually asked
    /// for is allowed to make it stick.
    private func commitTuning() { }

    private func persistTuningAfterSuccessfulGeneration() {
        guard var updated = person, updated.voiceTuning != draftTuning else { return }
        updated.tuning = draftTuning
        library.update(updated)
    }

    // MARK: Composer variants

    private var editor: some View {
        Panel {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                TextEditor(text: $text)
                    .font(Theme.Font.spoken)
                    .foregroundStyle(Theme.Palette.ink)
                    .frame(minHeight: 120)
                    .scrollContentBackground(.hidden)
                    .multilineTextAlignment(TextDirection.isArabic(text) ? .trailing : .leading)
                    .environment(\.layoutDirection,
                                  TextDirection.isArabic(text) ? .rightToLeft : .leftToRight)
                    .overlay(alignment: .topLeading) {
                        if trimmed.isEmpty {
                            Text(L("Write the words here…"))
                                .font(Theme.Font.spoken)
                                .foregroundStyle(Theme.Palette.inkSoft.opacity(0.6))
                                .padding(.top, 8)
                                .allowsHitTesting(false)
                        }
                    }

                HStack {
                    DictateButton(text: $text)
                    Spacer()
                    Text(Counts.characters(trimmed.count, limit: intent.characterLimit))
                        .font(Theme.Font.caption)
                        .foregroundStyle(trimmed.count > intent.characterLimit
                                         ? Theme.Palette.danger : Theme.Palette.inkSoft)
                }
            }
        }
    }

    private var comfortPicker: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(L("Choose a line"))
                .font(Theme.Font.label)
                .foregroundStyle(Theme.Palette.ink)

            if let person {
                let mine = library.affirmations(for: person)
                if !mine.isEmpty {
                    Text(L("Your lines"))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.bronze)
                    ForEach(mine) { line in
                        Panel(padding: Theme.Space.s) {
                            HStack(alignment: .top, spacing: Theme.Space.s) {
                                Button { text = line.text } label: {
                                    Text(line.text)
                                        .font(Theme.Font.body)
                                        .foregroundStyle(Theme.Palette.ink)
                                        .multilineTextAlignment(
                                            TextDirection.isArabic(line.text) ? .trailing : .leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                Button { pendingLineDeletion = line } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.Palette.inkSoft)
                                        // Was 32: below the 44 the rest of the
                                        // app uses, and sitting right beside
                                        // the line's own tap target.
                                        .frame(width: Theme.Metric.touchTarget,
                                               height: Theme.Metric.touchTarget)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(L("Remove line"))
                            }
                        }
                    }
                    Text(L("Ready-made lines"))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.inkSoft)
                }
            }

            ForEach(Composer.affirmations) { affirmation in
                Panel(padding: Theme.Space.s) {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Button { text = affirmation.english } label: {
                            Text(affirmation.english)
                                .font(Theme.Font.body)
                                .foregroundStyle(Theme.Palette.ink)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        // The masthead is جدّتي — there has to be a one-tap route
                        // to Arabic, not just a preview of it.
                        Button { text = affirmation.arabic } label: {
                            HStack(spacing: 6) {
                                Text(affirmation.arabic)
                                    .font(Theme.Font.caption)
                                    .environment(\.layoutDirection, .rightToLeft)
                                Image(systemName: "arrow.up.left.circle")
                                    .font(.system(size: 10))
                            }
                            .foregroundStyle(Theme.Palette.bronze)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var fictionPicker: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(L("Choose a story"))
                .font(Theme.Font.label)
                .foregroundStyle(Theme.Palette.ink)
            ForEach(Composer.bedtimeStories) { story in
                Panel(padding: Theme.Space.s) {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Button { text = story.text } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(story.title)
                                        .font(Theme.Font.label)
                                        .foregroundStyle(Theme.Palette.ink)
                                    Spacer(minLength: 0)
                                    Text(L("Load in English"))
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Theme.Palette.wineInk)
                                }
                                Text(story.text)
                                    .font(Theme.Font.caption)
                                    .foregroundStyle(Theme.Palette.inkSoft)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Divider().overlay(Theme.Palette.hairline)

                        Button { text = story.textArabic } label: {
                            VStack(alignment: .trailing, spacing: 3) {
                                HStack {
                                    Text(L("Load in Arabic"))
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Theme.Palette.bronze)
                                    Spacer(minLength: 0)
                                    Text(story.titleArabic)
                                        .font(Theme.Font.label)
                                        .foregroundStyle(Theme.Palette.ink)
                                }
                                Text(story.textArabic)
                                    .font(Theme.Font.caption)
                                    .foregroundStyle(Theme.Palette.inkSoft)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                            // No layoutDirection override here: `.trailing`
                            // already resolves to the right edge under the
                            // app's LTR layout. Setting both flipped it back.
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// What this screen has made before. Kept clips used to land in one shared
    /// pile with no way back to the experience that produced them.
    /// Which experiences a screen shelves. "A memory, retold" is the shelf for
    /// everything kept from it AND from Say something, so a line worth keeping
    /// has one place to live rather than disappearing into a general pile.
    private func isAlreadySaved(_ line: String, for person: Person) -> Bool {
        library.affirmations(for: person).contains {
            $0.text.trimmingCharacters(in: .whitespacesAndNewlines) == line
        }
    }

    private var shelvedIntents: Set<Intent> {
        switch intent {
        case .storyFromMemories: return [.storyFromMemories, .saySomething]
        default:                 return [intent]
        }
    }

    private var shelfTitle: String {
        switch intent {
        case .comfort:           return L("Comfort you have kept")
        case .storyFiction:      return L("Stories you have kept")
        case .storyFromMemories: return L("Words you have kept")
        default:                 return L("Previously kept")
        }
    }

    @ViewBuilder private var savedFromHere: some View {
        if let person {
            let mine = library.savedAssets(for: person, intents: shelvedIntents)
            if !mine.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Divider().overlay(Theme.Palette.hairline)
                    Text(shelfTitle)
                        .font(Theme.Font.label)
                        .foregroundStyle(Theme.Palette.ink)
                    ForEach(mine) { asset in
                        AudioRow(asset: asset) { generated = asset }
                    }
                }
                .padding(.top, Theme.Space.s)
            }
        }
    }

    // MARK: Behaviour

    private func seedIfNeeded() {
        draftTuning = person?.voiceTuning ?? .natural
        guard trimmed.isEmpty else { return }
        if intent == .comfort { text = uiIsArabic ? Composer.affirmations[0].arabic : Composer.affirmations[0].english }
    }

    /// The label stored WITH the audio. It describes what these words actually
    /// are, not which screen produced them.
    private func provenanceForCurrentText() -> String? {
        switch intent {
        case .storyFiction:
            return L("These are invented stories, not memories or stories told by this person.")
        case .askAboutThem:
            // The question, kept beside the answer it produced, so a clip can
            // still be traced back to what was actually asked.
            return L("You asked:") + " " + trimmed
        case .bridgeLanguage:
            return L("You wrote:") + " " + trimmed
        case .saySomething, .comfort, .storyFromMemories, .readBook:
            // Words a person typed. The content badge already says whose.
            return nil
        }
    }

    /// The words that actually get spoken.
    ///
    /// For most experiences this is exactly what was typed. `askAboutThem` and
    /// `bridgeLanguage` transform it first, and the RESULT is what the clip is
    /// labelled with — storing the question and playing the answer would leave
    /// an archive whose captions do not match its audio.
    private func resolveSpokenText(for person: Person) async throws -> String {
        switch intent {
        case .askAboutThem:
            return try await FamilyAnswerService()
                .answer(question: trimmed, notes: library.memories(for: person))
        case .bridgeLanguage:
            return try await TranslatorService().translate(trimmed)
        case .saySomething, .comfort, .storyFiction, .storyFromMemories, .readBook:
            return trimmed
        }
    }

    /// RIFF header means WAV (the debug mock); anything else is the provider's MP3.
    static func audioExtension(for data: Data) -> String {
        data.starts(with: Array("RIFF".utf8)) ? "wav" : "mp3"
    }

    private func speak() async {
        guard let person, let voiceId = person.voiceId, canSpeak else { return }
        isGenerating = true
        errorText = nil
        errorAllowsRetry = true
        failure = nil

        let model = useFastModel ? AppConfig.fastModelId : AppConfig.defaultModelId
        let service: VoiceService = AppConfig.voiceService()
        let provenance = provenanceForCurrentText()

        // Two experiences put a step between what was typed and what is spoken:
        // a question becomes an answer drawn from the family's notes, and a
        // sentence becomes its translation. It runs BEFORE the voice service is
        // touched, so a refusal costs nothing and is reported as an answer
        // rather than as a failed generation.
        let words: String
        do {
            words = try await resolveSpokenText(for: person)
        } catch is NotInNotes {
            isGenerating = false
            errorAllowsRetry = false
            failure = nil
            errorText = NotInNotes().errorDescription
            return
        } catch is ConsentMissing {
            isGenerating = false
            errorAllowsRetry = false
            failure = nil
            errorText = AppConfig.unavailableMessage
            return
        } catch {
            isGenerating = false
            errorAllowsRetry = true
            errorText = error.localizedDescription
            return
        }
        guard !words.isEmpty else { isGenerating = false; return }

        do {
            let data = try await service.synthesize(text: words,
                                                    voiceId: voiceId,
                                                    modelId: model,
                                                    tuning: draftTuning)
            let duration = (try? AVAudioPlayer(data: data))?.duration ?? 0
            let asset = library.storeAudio(data: data,
                                           for: person,
                                           source: .generated,
                                           text: words,
                                           duration: duration,
                                           modelId: model,
                                           provenance: provenance,
                                           intent: intent,
                                           content: intent.defaultContentProvenance,
                                           isSaved: false,
                                           fileExtension: Self.audioExtension(for: data))
            isGenerating = false
            persistTuningAfterSuccessfulGeneration()
            if let asset {
                generated = asset
            } else {
                errorAllowsRetry = false
                errorText = L("The audio arrived but could not be saved to this phone.")
            }
        } catch is ConsentMissing {
            isGenerating = false
            // Not a failure to retry: nothing is wrong at the far end, the app
            // has simply been told not to reach it.
            errorAllowsRetry = false
            failure = nil
            errorText = AppConfig.unavailableMessage
        } catch {
            isGenerating = false
            // The typed text is deliberately left untouched.
            let known = error as? VoiceServiceError
            errorAllowsRetry = !(known == .unauthorised
                                 || known == .outOfCredits
                                 || known == .voiceLimitReached
                                 || known == .notConfigured
                                 // The request was abandoned client-side after
                                 // 120s; the provider may well have finished it
                                 // and billed for it. Retrying pays twice.
                                 || known == .timedOut)
            failure = known
            errorText = known?.errorDescription ?? L("Something went wrong. Try again.")
        }
    }
}

/// Good-enough script detection to get alignment and direction right for the
/// mixed Arabic/English copy this app deals in.
enum TextDirection {
    static func isArabic(_ string: String) -> Bool {
        for scalar in string.unicodeScalars {
            let v = scalar.value
            if (0x0600...0x06FF).contains(v)      // Arabic
                || (0x0750...0x077F).contains(v)  // Arabic Supplement
                || (0xFB50...0xFDFF).contains(v)  // Presentation Forms-A
                || (0xFE70...0xFEFF).contains(v)  // Presentation Forms-B
            { return true }
        }
        return false
    }
}
