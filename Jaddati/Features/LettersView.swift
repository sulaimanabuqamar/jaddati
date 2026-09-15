import SwiftUI
import AVFoundation

/// Words sealed now, to be heard on a day that has not come.
///
/// The audio is made when a letter is OPENED and never in advance. Generating
/// early would spend the allowance on something nobody may ever hear, and would
/// fix a voice that might still be improved before the day arrives.
///
/// There is no background delivery here, and inventing one would be the
/// dishonest version of this feature. What actually happens is that a letter
/// becomes openable on its day, and the screen says exactly that.
struct LettersView: View {
    let personId: UUID

    @EnvironmentObject private var library: Library
    @ObservedObject private var localization = Localization.shared

    @State private var draft: String = ""
    @State private var occasion: String = ""
    @State private var deliverAt: Date = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var working = false
    @State private var errorText: String?
    @State private var generated: AudioAsset?
    @State private var pendingRemoval: Letter?
    /// Letters with a generation in flight. `working` alone is not enough:
    /// a @State write is not visible to a second tap that lands in the same
    /// run loop pass, and the second generation would be billed.
    @State private var opening: Set<UUID> = []
    /// Sending ONE sealed letter to somebody else's phone. Held per letter, so
    /// the code appears under the letter it belongs to rather than at the
    /// bottom of a screen that may be showing six of them.
    @State private var sendingLetter: UUID?
    @State private var letterCodeFor: UUID?
    @State private var letterCode: String?
    @State private var letterCodeProblem: String?

    private var person: Person? { library.people.first { $0.id == personId } }
    private var trimmed: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }
    private let limit = 800

    /// Tomorrow at the earliest. A letter dated today is not a letter, it is
    /// just words.
    private var earliest: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    }

    private var canSeal: Bool {
        !trimmed.isEmpty && trimmed.count <= limit && !working && !library.loadFailed
    }

    var body: some View {
        VStack(spacing: 0) {
            AppBar(title: L("Words that arrive later"))

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    Group {
                        if let person {
                            Breadcrumb(name: person.name,
                                       relationship: person.relationship,
                                       photo: library.photoURL(for: person))
                        }
                        Headline(text: L("Sealed now.\nHeard later."))
                        SubText(text: L("Write something now and choose the day it can be heard. Nothing is created until you open it, and until then the words stay sealed on this phone."))
                    }

                    if !AppConfig.isConfigured {
                        ErrorNote(message: AppConfig.unavailableMessage)
                    }
                    if let errorText {
                        ErrorNote(message: errorText)
                    }

                    if let person, !openable(for: person).isEmpty {
                        waiting(for: person)
                    }

                    composer

                    if let person, !library.sealedLetters(for: person).isEmpty {
                        sealedList(for: person)
                    }

                    if let person, !library.openedLetters(for: person).isEmpty {
                        openedList(for: person)
                    }

                    if let person, library.letters(for: person).isEmpty {
                        EmptyHint(icon: "lock",
                                  title: L("Nothing sealed yet"),
                                  message: L("Write something for a day that has not come."))
                    }
                }
                .padding(.horizontal, Theme.Metric.screenPadding)
                .padding(.bottom, Theme.Space.xl)
            }
        }
        .background(Theme.Palette.paper)
        .navigationDestination(item: $generated) { asset in
            PlayerView(asset: asset)
        }
        .confirmationDialog(L("Remove this letter?"),
                            isPresented: Binding(get: { pendingRemoval != nil },
                                                 set: { if !$0 { pendingRemoval = nil } }),
                            titleVisibility: .visible) {
            Button(L("Remove"), role: .destructive) {
                if let letter = pendingRemoval { library.removeLetter(letter.id) }
                pendingRemoval = nil
            }
            Button(L("Cancel"), role: .cancel) { pendingRemoval = nil }
        } message: {
            Text(L("The words are deleted from this phone. This cannot be undone."))
        }
    }

    // MARK: Ready

    private func waiting(for person: Person) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionLabel(text: L("Waiting for you"))
            ForEach(openable(for: person)) { letter in
                Panel {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        HStack {
                            Text(letter.occasion.isEmpty ? L("A letter for today") : letter.occasion)
                                .font(Theme.Font.label)
                                .foregroundStyle(Theme.Palette.ink)
                            Spacer()
                            Text(L("Ready"))
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Palette.wineInk)
                        }
                        Text(L("Sealed on") + " " + Self.dateText(letter.createdAt))
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Palette.inkSoft)
                        Button(opening.contains(letter.id) ? L("Opening…") : L("Open it")) {
                            Task { await open(letter) }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        // loadFailed means save() is guaranteed to fail, so the
                        // clip would be billed and then thrown away. CreateView
                        // has always guarded on this; this screen did not.
                        .disabled(working || person.hasVoice != true
                                  || !AppConfig.isConfigured || library.loadFailed)
                    }
                }
            }
        }
    }

    /// Due, plus any letter whose clip no longer exists.
    ///
    /// Opening marked the letter and handed the clip to the player, where
    /// Discard deletes it. The letter was then in neither list: no Open button,
    /// no Remove button, and the opened list showed only an occasion and a
    /// date. The words were gone from the product entirely while the row still
    /// sat there naming the birthday they were written for.
    private func openable(for person: Person) -> [Letter] {
        library.letters(for: person).filter { letter in
            if letter.isDue { return true }
            guard letter.isOpened, letter.deliverAt <= Date() else { return false }
            guard let id = letter.assetId,
                  let asset = library.assets.first(where: { $0.id == id }) else { return true }
            return !library.fileExists(for: asset)
        }
    }

    // MARK: Sealing

    private var composer: some View {
        Panel {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionLabel(text: L("Seal something new"))

                VStack(alignment: .leading, spacing: 6) {
                    Text(L("The occasion"))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.inkSoft)
                    TextField(L("A birthday, a graduation, a wedding…"), text: $occasion)
                        .textFieldStyle(.plain)
                        .padding(Theme.Space.s)
                        .background(Theme.Palette.ivorySunk,
                                    in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                }

                DatePicker(L("The day it can be heard"),
                           selection: $deliverAt,
                           in: earliest...,
                           displayedComponents: .date)
                    .font(Theme.Font.caption)

                TextEditor(text: $draft)
                    .frame(minHeight: 120)
                    .font(Theme.Font.body)
                    .multilineTextAlignment(TextDirection.isArabic(draft) ? .trailing : .leading)
                    .scrollContentBackground(.hidden)
                    .padding(Theme.Space.xs)
                    .background(Theme.Palette.ivorySunk,
                                in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        if draft.isEmpty {
                            Text(L("Write what they should say when the day comes…"))
                                .font(Theme.Font.body)
                                .foregroundStyle(Theme.Palette.inkSoft)
                                .padding(Theme.Space.s)
                                .allowsHitTesting(false)
                        }
                    }

                Text(Counts.characters(trimmed.count, limit: limit))
                    .font(Theme.Font.caption)
                    .foregroundStyle(trimmed.count > limit ? Theme.Palette.danger : Theme.Palette.inkSoft)

                Button(L("Seal it")) { seal() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!canSeal)
            }
        }
    }

    @MainActor
    private func seal() {
        guard let person, canSeal else { return }
        // Noon rather than midnight: a letter dated for a birthday should
        // arrive during that day, not in the small hours of it.
        let day = Calendar.current.startOfDay(for: deliverAt)
        let noon = Calendar.current.date(byAdding: .hour, value: 12, to: day) ?? deliverAt
        library.addLetter(for: person, text: trimmed,
                          occasion: occasion.trimmingCharacters(in: .whitespacesAndNewlines),
                          deliverAt: noon)
        draft = ""
        occasion = ""
    }

    // MARK: Sealed, and opened

    /// Shows the occasion and the date, never the words. Being able to read it
    /// early is the same as not having sealed it.
    private func sealedList(for person: Person) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionLabel(text: L("Sealed"))
            ForEach(library.sealedLetters(for: person)) { letter in
                Panel(padding: Theme.Space.s) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(letter.occasion.isEmpty ? L("Sealed words") : letter.occasion)
                                .font(Theme.Font.label)
                                .foregroundStyle(Theme.Palette.ink)
                            Spacer()
                            Text(Self.dateText(letter.deliverAt))
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Palette.inkSoft)
                        }
                        Text(Counts.characters(letter.text.count, limit: limit) + " · " + L("Sealed until the day"))
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Palette.inkSoft)
                        HStack(spacing: 18) {
                            Button(L("Remove")) { pendingRemoval = letter }
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.Palette.wineInk)
                                .frame(minHeight: Theme.Metric.touchTarget, alignment: .leading)
                            // A seal that can only open on the phone that wrote
                            // it is a letter to yourself.
                            Button(sendingLetter == letter.id ? L("Preparing…") : L("Send it")) {
                                Task { await sendSeal(letter, of: person) }
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.Palette.wineInk)
                            .frame(minHeight: Theme.Metric.touchTarget, alignment: .leading)
                            .disabled(sendingLetter != nil)
                            Spacer(minLength: 0)
                        }
                        if letterCodeFor == letter.id {
                            if let letterCode { sealCode(letterCode) }
                            if let letterCodeProblem { ErrorNote(message: letterCodeProblem) }
                        }
                    }
                }
            }
        }
    }

    /// The code, under the letter it carries. Deliberately the same words as
    /// the handoff on Setup — one thing to learn, not two.
    private func sealCode(_ code: String) -> some View {
        VStack(spacing: 6) {
            Text(L("Read them this:"))
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
            Text(code)
                .font(Theme.Font.displayMedium(32))
                .kerning(7)
                .foregroundStyle(Theme.Palette.wineInk)
                // Latin characters whichever language the app is in, so this
                // must not mirror with the rest of the screen.
                .environment(\.layoutDirection, .leftToRight)
            Text(L("They open Jaddati, choose Bring someone from another phone, and type it."))
                .font(.system(size: 11))
                .foregroundStyle(Theme.Palette.inkSoft)
                .multilineTextAlignment(.center)
            Text(L("Only this letter travels, still sealed. It opens on their phone on the day."))
                .font(.system(size: 11))
                .foregroundStyle(Theme.Palette.inkSoft)
                .multilineTextAlignment(.center)
            Text(L("The code works for a day."))
                .font(.system(size: 11))
                .foregroundStyle(Theme.Palette.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: Theme.Metric.cardRadius)
                .fill(Theme.Palette.sunk)
                .overlay(RoundedRectangle(cornerRadius: Theme.Metric.cardRadius)
                    .stroke(Theme.Palette.hairline, lineWidth: 1))
        )
        .padding(.top, 4)
    }

    @MainActor
    private func sendSeal(_ letter: Letter, of person: Person) async {
        sendingLetter = letter.id
        letterCodeFor = letter.id
        letterCode = nil
        letterCodeProblem = nil
        defer { sendingLetter = nil }
        do {
            letterCode = try await Archive.sendLetter(letter, of: person, library: library).code
        } catch is ConsentMissing {
            letterCodeProblem = AppConfig.unavailableMessage
        } catch {
            letterCodeProblem = (error as? LocalizedError)?.errorDescription
                ?? L("The code could not be created. Try again.")
        }
    }

    private func openedList(for person: Person) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionLabel(text: L("Already opened"))
            ForEach(library.openedLetters(for: person)) { letter in
                VStack(alignment: .leading, spacing: 2) {
                    Text((letter.occasion.isEmpty ? L("Sealed words") : letter.occasion)
                         + " · " + Self.dateText(letter.deliverAt))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.inkSoft)
                    // The words themselves, once the day has passed. Before it,
                    // nothing shows them; after it, they must not be reachable
                    // only through a clip that can be discarded.
                    BidiText(value: letter.text, font: Theme.Font.body)
                }
            }
        }
    }

    // MARK: Opening

    /// Marked @MainActor deliberately. A nonisolated async method does not
    /// inherit the caller's actor under Swift 5, so every @State write below —
    /// including `generated`, which drives navigation — was happening off the
    /// main thread. It also meant the `opening` guard could not hold: two taps
    /// could both read it before either wrote, and the second generation was
    /// billed.
    @MainActor
    private func open(_ letter: Letter) async {
        guard let person, let voiceId = person.voiceId else { return }
        guard !working, !opening.contains(letter.id), !letter.isOpened else { return }
        opening.insert(letter.id)
        working = true
        errorText = nil

        let service: VoiceService = AppConfig.voiceService()
        let model = AppConfig.defaultModelId
        do {
            let data = try await service.synthesize(text: letter.text,
                                                    voiceId: voiceId,
                                                    modelId: model,
                                                    tuning: person.voiceTuning)
            let duration = (try? AVAudioPlayer(data: data))?.duration ?? 0
            let asset = library.storeAudio(data: data,
                                           for: person,
                                           source: .generated,
                                           text: letter.text,
                                           duration: duration,
                                           modelId: model,
                                           provenance: L("Sealed on") + " " + Self.dateText(letter.createdAt),
                                           intent: .saySomething,
                                           content: .wordsSuppliedByYou,
                                           isSaved: true,
                                           fileExtension: CreateView.audioExtension(for: data))
            working = false
            opening.remove(letter.id)
            if let asset {
                var opened = letter
                opened.openedAt = Date()
                opened.assetId = asset.id
                library.update(opened)
                generated = asset
            } else {
                errorText = L("The audio arrived but could not be saved to this phone.")
            }
        } catch is ConsentMissing {
            working = false
            opening.remove(letter.id)
            errorText = AppConfig.unavailableMessage
        } catch {
            working = false
            opening.remove(letter.id)
            errorText = error.localizedDescription
        }
    }

    private static func dateText(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: uiIsArabic ? "ar" : "en")
        f.dateStyle = .long
        f.timeStyle = .none
        return f.string(from: date)
    }
}
