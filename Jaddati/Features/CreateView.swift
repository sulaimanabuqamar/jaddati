import SwiftUI
import AVFoundation

/// Decide the words, then hear them. One screen per intent, one primary action.
struct CreateView: View {
    let personId: UUID
    let intent: Intent

    @EnvironmentObject private var library: Library

    @State private var text: String = ""
    @State private var newNote: String = ""
    @State private var isGenerating = false
    @State private var errorText: String?
    @State private var generated: AudioAsset?
    @State private var useFastModel = false

    /// The exact string the retelling builder produced, if it was used.
    /// Provenance is claimed by comparing against this — opening the "memory"
    /// screen and typing something new must NOT get a family-memory label.
    @State private var builtRetelling: String?

    private var person: Person? { library.person(withId: personId) }

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var noteCount: Int {
        guard let person else { return 0 }
        return library.notes(for: person).count
    }

    /// The screen-level hint. On the retelling screen it must not promise the
    /// family's words when the family has not written any.
    private var screenNote: String? {
        switch intent {
        case .storyFiction:
            return "An invented story. Not a real memory."
        case .storyFromMemories:
            return noteCount == 0
                ? "Nothing to retell yet. Add a memory below, in your family's own words."
                : "A retelling uses only your family's words. Nothing is invented."
        case .saySomething, .comfort:
            return nil
        }
    }

    /// Why the button is greyed out. Shown under it, because a disabled control
    /// that gives no reason reads as broken.
    private var disabledReason: String? {
        if isGenerating || canSpeak { return nil }
        if !AppConfig.isConfigured { return nil }        // has its own error note above
        if person?.hasVoice != true { return "This person has no voice yet." }
        if trimmed.count > AppConfig.maxCharactersPerGeneration {
            return "That is longer than \(AppConfig.maxCharactersPerGeneration) characters."
        }
        switch intent {
        case .saySomething:
            return "Type something for them to say."
        case .comfort:
            return "Tap one of the lines above, or write your own."
        case .storyFiction:
            return "Tap one of the stories above to load it, or write your own."
        case .storyFromMemories:
            return noteCount == 0
                ? "Add a memory first — the app will not invent one for you."
                : "Tap Build the retelling above, or write your own words."
        }
    }

    private var canSpeak: Bool {
        !trimmed.isEmpty
            && trimmed.count <= AppConfig.maxCharactersPerGeneration
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

                    switch intent {
                    case .saySomething:      EmptyView()
                    case .comfort:           comfortPicker
                    case .storyFiction:      fictionPicker
                    case .storyFromMemories: memoriesSource
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

                    if let errorText {
                        ErrorNote(message: errorText) {
                            self.errorText = nil
                            Task { await speak() }
                        }
                    }

                    Button(isGenerating ? "Speaking…" : "Hear it in their voice") {
                        Task { await speak() }
                    }
                    .buttonStyle(PrimaryButtonStyle(enabled: canSpeak))
                    .disabled(!canSpeak)

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
        .onAppear(perform: seedIfNeeded)
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
                    Text("\(trimmed.count) / \(AppConfig.maxCharactersPerGeneration)")
                        .font(Theme.Font.caption)
                        .foregroundStyle(trimmed.count > AppConfig.maxCharactersPerGeneration
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
            Text("Choose a story")
                .font(Theme.Font.label)
                .foregroundStyle(Theme.Palette.ink)
            ForEach(Composer.bedtimeStories) { story in
                Button { text = story.text } label: {
                    Panel(padding: Theme.Space.s) {
                        HStack(alignment: .top, spacing: Theme.Space.s) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(story.title)
                                    .font(Theme.Font.label)
                                    .foregroundStyle(Theme.Palette.ink)
                                Text(story.text)
                                    .font(Theme.Font.caption)
                                    .foregroundStyle(Theme.Palette.inkSoft)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                            Text("Use")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.Palette.forest)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var memoriesSource: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Your family's memories")
                .font(Theme.Font.label)
                .foregroundStyle(Theme.Palette.ink)

            if let person {
                let notes = library.notes(for: person)
                if notes.isEmpty {
                    Text("Nothing written down yet. A retelling is built only from what your family adds here — the app will not invent a memory.")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(notes) { note in
                        Panel(padding: Theme.Space.s) {
                            Text(note.text)
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Palette.ink)
                        }
                    }
                    Button("Build the retelling") {
                        let built = Composer.retelling(from: notes) ?? ""
                        text = built
                        builtRetelling = built
                    }
                    .buttonStyle(QuietButtonStyle())
                }

                Panel(padding: Theme.Space.s) {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        TextField("Add a memory in your own words…", text: $newNote, axis: .vertical)
                            .font(Theme.Font.body)
                            .lineLimit(1...4)
                        Button("Save memory") {
                            let clean = newNote.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !clean.isEmpty else { return }
                            library.add(FamilyNote(personId: person.id, text: clean))
                            newNote = ""
                        }
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.forest)
                    }
                }
            }
        }
    }

    // MARK: Behaviour

    private func seedIfNeeded() {
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
        case .storyFromMemories:
            // Only claim the family's authority if the family's words are what
            // is about to be spoken.
            if let built = builtRetelling, trimmed == built.trimmingCharacters(in: .whitespacesAndNewlines) {
                return "Retold from memories your family wrote down."
            }
            return "Written by you. Not taken from a recorded memory."
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

        let model = useFastModel ? AppConfig.fastModelId : AppConfig.defaultModelId
        let service: VoiceService = AppConfig.voiceService()
        let words = trimmed
        let provenance = provenanceForCurrentText()

        do {
            let data = try await service.synthesize(text: words, voiceId: voiceId, modelId: model)
            let duration = (try? AVAudioPlayer(data: data))?.duration ?? 0
            let asset = library.storeAudio(data: data,
                                           for: person,
                                           source: .generated,
                                           text: words,
                                           duration: duration,
                                           modelId: model,
                                           provenance: provenance,
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
            errorText = (error as? VoiceServiceError)?.errorDescription
                ?? "Something went wrong. Try again."
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
