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

    private var person: Person? { library.people.first { $0.id == personId } }
    private var trimmed: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }
    private let limit = 800

    /// Tomorrow at the earliest. A letter dated today is not a letter, it is
    /// just words.
    private var earliest: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    }

    private var canSeal: Bool {
        !trimmed.isEmpty && trimmed.count <= limit && !working
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

                    if let person, !library.dueLetters(for: person).isEmpty {
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
            ForEach(library.dueLetters(for: person)) { letter in
                Panel {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        HStack {
                            Text(letter.occasion.isEmpty ? L("A letter for today") : letter.occasion)
                                .font(Theme.Font.label)
                                .foregroundStyle(Theme.Palette.ink)
                            Spacer()
                            Text(L("Ready"))
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Palette.forest)
                        }
                        Text(L("Sealed on") + " " + Self.dateText(letter.createdAt))
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Palette.inkSoft)
                        Button(working ? L("Opening…") : L("Open it")) {
                            Task { await open(letter) }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(working || person.hasVoice != true || !AppConfig.isConfigured)
                    }
                }
            }
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

                Text("\(trimmed.count) / \(limit)")
                    .font(Theme.Font.caption)
                    .foregroundStyle(trimmed.count > limit ? Theme.Palette.danger : Theme.Palette.inkSoft)

                Button(L("Seal it")) { seal() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!canSeal)
            }
        }
    }

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
                        Text("\(letter.text.count) / \(limit) · " + L("Sealed until the day"))
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Palette.inkSoft)
                        Button(L("Remove")) { pendingRemoval = letter }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.Palette.wine)
                            .frame(minHeight: Theme.Metric.touchTarget, alignment: .leading)
                    }
                }
            }
        }
    }

    private func openedList(for person: Person) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionLabel(text: L("Already opened"))
            ForEach(library.openedLetters(for: person)) { letter in
                Text((letter.occasion.isEmpty ? L("Sealed words") : letter.occasion)
                     + " · " + Self.dateText(letter.deliverAt))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
        }
    }

    // MARK: Opening

    private func open(_ letter: Letter) async {
        guard let person, let voiceId = person.voiceId, !working else { return }
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
            errorText = AppConfig.unavailableMessage
        } catch {
            working = false
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
