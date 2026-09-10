import SwiftUI
import AVFoundation

/// Decide the words, then hear them. One screen per intent, one primary action.
struct CreateView: View {
    let personId: UUID
    let intent: Intent

    @EnvironmentObject private var library: Library

    @State private var text: String = ""
    @State private var isGenerating = false
    @State private var errorText: String?
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
    private var screenNote: String? {
        switch intent {
        case .storyFiction:
            return "An invented story. Not a real memory."
        case .readBook:
            return "Read from a file you provided."
        case .saySomething, .comfort, .storyFromMemories:
            return nil
        }
    }

    /// Why the button is greyed out. Shown under it, because a disabled control
    /// that gives no reason reads as broken.
    private var disabledReason: String? {
        if isGenerating || canSpeak { return nil }
        if !AppConfig.isConfigured { return nil }        // has its own error note above
        if person?.voiceIsUnavailableHere == true {
            return "This voice was made in test mode. Create the real one from the profile."
        }
        if person?.hasVoice != true { return "This person has no voice yet." }
        if trimmed.count > intent.characterLimit {
            return "That is longer than \(intent.characterLimit) characters."
        }
        switch intent {
        case .saySomething:
            return "Type something for them to say."
        case .comfort:
            return "Tap one of the lines above, or write your own."
        case .storyFiction:
            return "Tap one of the stories above to load it, or write your own."
        case .storyFromMemories, .readBook:
            return "Type something for them to say."
        }
    }

    private var canSpeak: Bool {
        !trimmed.isEmpty
            && trimmed.count <= intent.characterLimit
            && !isGenerating
            && person?.hasVoice == true
            && AppConfig.isConfigured
    }

    var body: some View {
        ZStack {
            Theme.Palette.ivory.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(intent.title)
                            .font(Theme.Font.title)
                            .foregroundStyle(Theme.Palette.ink)
                        Text(intent.subtitle)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Palette.inkSoft)
                    }

                    if !AppConfig.isConfigured {
                        ErrorNote(message: "Voices aren't set up on this build, so nothing can be generated. Saved memories still play.")
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

                    actionSection
                    if intent != .storyFromMemories { savedFromHere }
                }
                .padding(Theme.Space.m)
                .padding(.bottom, Theme.Space.xl)
            }
            // Swiping the page down puts the keyboard away, so the primary
            // action is reachable without hunting for a Done button.
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $generated) { asset in
            PlayerView(asset: asset)
        }
        .sheet(isPresented: $addingVoice) {
            AddVoiceView(personId: personId)
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
                ErrorNote(message: errorText) {
                    self.errorText = nil
                    self.failure = nil
                    Task { await speak() }
                }
                if isRecoverableByRecreatingVoice {
                    Button("Add their voice again") { addingVoice = true }
                        .buttonStyle(QuietButtonStyle())
                }
            }
        }

        Button(isGenerating ? "Speaking…" : "Hear it in their voice") {
            Task { await speak() }
        }
        .buttonStyle(PrimaryButtonStyle(enabled: canSpeak))
        .disabled(!canSpeak)

        if intent == .comfort, let person, !trimmed.isEmpty, !isAlreadySaved(trimmed, for: person) {
            Button("Add this line to my list") {
                library.add(FamilyNote(personId: person.id,
                                       text: trimmed,
                                       kind: FamilyNote.affirmationKind))
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
                Text("Generating. Your words stay here if it fails.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
        }

        Toggle("Faster, slightly plainer voice", isOn: $useFastModel)
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
                HStack(spacing: Theme.Space.xs) {
                    tuningPreset("Natural", .natural)
                    tuningPreset("Steady", .steady)
                    tuningPreset("Warm", .warm)
                }

                slider("Steadiness",
                       help: "Higher is more even and predictable. Lower carries more feeling, and occasionally a strange reading.",
                       value: $draftTuning.stability)

                slider("Likeness",
                       help: "How hard to push towards the original recording. Very high also reproduces any noise in it.",
                       value: $draftTuning.similarity)

                paceSlider

                Text("Changes apply to the next thing you generate.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
            .padding(.top, Theme.Space.xs)
        } label: {
            HStack {
                Text("Voice character")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
                if let name = draftTuning.presetName {
                    Text(name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.Palette.bronze)
                }
            }
        }
        .tint(Theme.Palette.forest)
    }

    private func tuningPreset(_ name: String, _ value: VoiceTuning) -> some View {
        Button {
            draftTuning = value
            commitTuning()
        } label: {
            Text(name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(draftTuning == value ? Theme.Palette.ivory : Theme.Palette.forest)
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
                Text("Pace")
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
            Text("Lower is slower and easier to follow. Much below 0.80 the voice starts to drag.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func commitTuning() {
        guard var updated = person else { return }
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
                            Text("Type the words you want to hear…")
                                .font(Theme.Font.spoken)
                                .foregroundStyle(Theme.Palette.inkSoft.opacity(0.6))
                                .padding(.top, 8)
                                .allowsHitTesting(false)
                        }
                    }

                HStack {
                    Spacer()
                    Text("\(trimmed.count) / \(intent.characterLimit)")
                        .font(Theme.Font.caption)
                        .foregroundStyle(trimmed.count > intent.characterLimit
                                         ? Theme.Palette.danger : Theme.Palette.inkSoft)
                }
            }
        }
    }

    private var comfortPicker: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Tap a line to load it, or write your own below")
                .font(Theme.Font.label)
                .foregroundStyle(Theme.Palette.ink)

            if let person {
                let mine = library.affirmations(for: person)
                if !mine.isEmpty {
                    Text("Yours")
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
                                Button { library.removeNote(line) } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.Palette.inkSoft)
                                        .frame(width: 32, height: 32)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove this line")
                            }
                        }
                    }
                    Text("Ready-made")
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
            Text("Tap a story to load it, in either language")
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
                                    Text("English")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Theme.Palette.forest)
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
                                    Text("العربية")
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
        case .comfort:           return "Comfort you have kept"
        case .storyFiction:      return "Stories you have kept"
        case .storyFromMemories: return "Everything you have kept"
        default:                 return "Kept from here"
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
        if intent == .comfort { text = Composer.affirmations[0].english }
    }

    /// The label stored WITH the audio. It describes what these words actually
    /// are, not which screen produced them.
    private func provenanceForCurrentText() -> String? {
        switch intent {
        case .saySomething, .comfort:
            return nil
        case .storyFiction:
            return "An invented story. Not a real memory."
        case .storyFromMemories, .readBook:
            // Words a person typed. Nothing to disclaim.
            return nil
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
        failure = nil

        let model = useFastModel ? AppConfig.fastModelId : AppConfig.defaultModelId
        let service: VoiceService = AppConfig.voiceService()
        let words = trimmed
        let provenance = provenanceForCurrentText()

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
                                           isSaved: false,
                                           fileExtension: Self.audioExtension(for: data))
            isGenerating = false
            if let asset {
                generated = asset
            } else {
                errorText = "The audio arrived but could not be saved to this phone."
            }
        } catch {
            isGenerating = false
            // The typed text is deliberately left untouched.
            let known = error as? VoiceServiceError
            failure = known
            errorText = known?.errorDescription ?? "Something went wrong. Try again."
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
