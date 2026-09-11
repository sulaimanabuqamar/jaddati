import SwiftUI
import PhotosUI
import ImageIO

/// One loved one. The voice and the ways to hear it are the whole screen.
struct PersonView: View {
    let personId: UUID

    @EnvironmentObject private var library: Library
    @State private var addingVoice = false
    #if DEBUG
    /// Not read anywhere. It exists so this screen re-renders when offline test
    /// mode is toggled — `AppConfig.isUsingMock` reads UserDefaults directly and
    /// publishes nothing, so without this the voice gating would show stale.
    @AppStorage(AppConfig.mockDefaultsKey) private var useMockVoices = false
    #endif
    /// Declared but never read, like the mock flag above it. `AppConfig`'s
    /// three availability flags now depend on the consent answer, which lives
    /// in UserDefaults and publishes nothing — so without an observer here,
    /// withdrawing consent from the home screen would leave this screen's
    /// controls live until something else happened to redraw it. The pager
    /// keeps every tab alive, so that "something else" may never come.
    ///
    /// Outside the DEBUG block on purpose: inside it, the shipping build —
    /// the only one a reviewer or a family ever runs — would not observe it.
    @EnvironmentObject private var consent: Consent
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false
    @State private var isDeleting = false
    @State private var deleteProblem: String?
    @State private var photoPick: PhotosPickerItem?
    @State private var checkingAvailability = false
    @State private var availabilityNote: String?

    private var person: Person? { library.person(withId: personId) }

    var body: some View {
        VStack(spacing: 0) {
            AppBar(title: person?.name ?? L("Jaddati"))

            if let person {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        profile(person)

                        if !AppConfig.isConfigured {
                            notConnectedNote.padding(.top, 21)
                        }

                        if person.hasVoice {
                            intents(person)
                        } else if person.voiceIsUnavailableHere {
                            placeholderVoice.padding(.top, 21)
                        } else if person.voicePendingVerification {
                            pendingVerification.padding(.top, 21)
                        } else {
                            noVoiceYet.padding(.top, 21)
                        }

                        originals(person)
                        savedLink(person)
                        deleteRow(person)
                    }
                    .padding(.horizontal, Theme.Metric.screenPadding)
                    .padding(.bottom, Theme.Space.xl)
                }
            } else {
                EmptyHint(icon: "person.slash",
                          title: L("No people yet"),
                          message: L("A place for voices you want to keep."))
                Spacer()
            }
        }
        .background(Theme.Palette.paper)
        .navigationBarHidden(true)
        .sheet(isPresented: $addingVoice) {
            if let person { AddVoiceView(personId: person.id) }
        }
        .onChange(of: photoPick) { _, item in
            guard let item, let person else { return }
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                let shrunk = data.flatMap { Self.downscale($0) }
                await MainActor.run {
                    if let shrunk { library.setPhoto(shrunk, for: person) }
                    photoPick = nil
                }
            }
        }
    }

    // MARK: Pieces

    private func profile(_ person: Person) -> some View {
        let photo = library.photoURL(for: person)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                PhotosPicker(selection: $photoPick, matching: .images, photoLibrary: .shared()) {
                    ZStack(alignment: .bottomTrailing) {
                        PersonAvatar(name: person.name, imageURL: photo, size: 88)
                        Image(systemName: photo == nil ? "plus" : "pencil")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.Palette.paper)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Theme.Palette.wine))
                            .overlay(Circle().stroke(Theme.Palette.paper, lineWidth: 2))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(photo == nil ? L("Add photo") : L("Change photo"))

                VStack(alignment: .leading, spacing: 5) {
                    BidiText(value: person.name,
                             font: Theme.Font.display(33),
                             colour: Theme.Palette.ink)
                    if !person.relationship.isEmpty {
                        BidiText(value: person.relationship,
                                 font: .system(size: 14),
                                 colour: Theme.Palette.inkSoft)
                    }
                    voiceTag(person)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 16)

            if photo != nil {
                Button(L("Remove photo")) { library.removePhoto(for: person) }
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .padding(.top, 10)
            }
        }
    }

    /// The one-line truth about whether this voice can speak.
    ///
    /// The words and the colour are picked in a plain function, NOT inside the
    /// ViewBuilder. A builder treats `if` as view construction, so assigning to
    /// a `let` in its branches hands the assignment to `buildExpression` and
    /// fails with "this expression does not conform to View".
    private func voiceTagContent(_ person: Person) -> (String, Color) {
        if person.voiceIsUnavailableHere {
            return (L("Test voice only"), Theme.Palette.danger)
        }
        if person.hasVoice {
            return (L("Recreated voice ready"), Theme.Palette.wine)
        }
        if person.voicePendingVerification {
            return (L("Voice is being prepared"), Theme.Palette.amber)
        }
        return (L("No recreated voice yet"), Theme.Palette.inkSoft)
    }

    private func voiceTag(_ person: Person) -> some View {
        let (words, tint) = voiceTagContent(person)
        return Text(words.uppercased())
            .font(.system(size: 9, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(tint.opacity(0.10))
            )
            .padding(.top, 3)
    }


    /// A library photo is many times larger than an 88-point arch needs, so it
    /// is shrunk once on import and the small version is what gets stored.
    ///
    /// Deliberately ImageIO rather than `UIImage(data:)` + redraw. A photo off
    /// the camera roll is around 12 megapixels, which decodes to roughly 48MB
    /// of bitmap, and drawing it into a smaller context holds a second buffer
    /// at the same time. That spike — on one tap, on top of everything else the
    /// app was holding — is what the OS killed the app for. This path never
    /// materialises the full-size image: the decoder is told the size we want
    /// and produces only that.
    private static func downscale(_ data: Data, to maxSide: CGFloat = 600) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // honour EXIF rotation
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxSide)
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return UIImage(cgImage: thumb).jpegData(compressionQuality: 0.85)
    }

    /// This voice was minted by the offline test mode and does not exist at the
    /// provider. Before this state existed the profile read "Voice ready", all
    /// four experiences unlocked, and every generation failed on an invalid id
    /// with no way to recover from the screen you were on.
    private var placeholderVoice: some View {
        Panel {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text(L("Test voice only"))
                    .font(Theme.Font.heading)
                    .foregroundStyle(Theme.Palette.ink)
                Text(L("Created in offline test mode. This is not a usable voice."))
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                Button(L("Create a real voice")) { addingVoice = true }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 2)
            }
        }
    }

    /// The provider accepted the sample but will not let the voice speak yet.
    /// Showing "Voice ready" here is exactly how you get a silent demo.
    private var pendingVerification: some View {
        Panel {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text(L("Voice is being prepared"))
                    .font(Theme.Font.heading)
                    .foregroundStyle(Theme.Palette.ink)
                Text(L("The voice has been created, but the service has not made it available yet."))
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)

                Button(checkingAvailability ? L("Checking…") : L("Check availability")) {
                    Task { await checkAvailability() }
                }
                .buttonStyle(PrimaryButtonStyle(enabled: canCheckAvailability))
                .disabled(!canCheckAvailability)
                .padding(.top, 2)

                if let availabilityNote {
                    Text(availabilityNote)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(L("Checking asks the service to say one short word."))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var canCheckAvailability: Bool {
        !checkingAvailability && AppConfig.isConfigured && person?.voiceId != nil
    }

    /// There is no "is it ready" endpoint. The only honest test is to use the
    /// voice: if the service speaks, the voice is available, and the flag that
    /// was holding the whole screen closed can come off.
    private func checkAvailability() async {
        guard let person, let voiceId = person.voiceId, canCheckAvailability else { return }
        checkingAvailability = true
        availabilityNote = nil
        do {
            _ = try await AppConfig.voiceService().synthesize(
                text: L("Hello"),
                voiceId: voiceId,
                modelId: AppConfig.defaultModelId,
                tuning: person.voiceTuning)
            var updated = person
            updated.voiceRequiresVerification = false
            library.update(updated)
            checkingAvailability = false
        } catch is ConsentMissing {
            checkingAvailability = false
            availabilityNote = AppConfig.unavailableMessage
        } catch {
            checkingAvailability = false
            availabilityNote = (error as? VoiceServiceError)?.errorDescription
                ?? L("The service has not made this voice available yet.")
        }
    }

    private var notConnectedNote: some View {
        Panel {
            VStack(alignment: .leading, spacing: 6) {
                Text(AppConfig.unavailableTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Palette.ink)
                SubText(text: AppConfig.unavailableMessage)
            }
        }
    }

    private var noVoiceYet: some View {
        Panel {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text(L("No recreated voice yet"))
                    .font(Theme.Font.heading)
                    .foregroundStyle(Theme.Palette.ink)
                Text(L("Add an original recording to create a voice.") + " " + L("About a minute. One voice. A quiet room."))
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                Button(L("Add their voice")) { addingVoice = true }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 2)
            }
        }
    }

    private func intents(_ person: Person) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(Intent.allCases.enumerated()), id: \.element) { index, intent in
                NavigationLink {
                    // Books are a shelf, not a compose box.
                    if intent == .readBook {
                        BooksView(personId: person.id)
                    } else {
                        CreateView(personId: person.id, intent: intent)
                    }
                } label: {
                    FeatureRow(icon: intent.icon,
                               title: intent.title,
                               subtitle: intent.subtitle,
                               emphasised: index == 0)
                }
                .buttonStyle(.plain)
                // The wine card is a card, not a list row. It was sitting hard
                // against the badge above it and the first plain row below,
                // which is what made it look wedged in rather than featured.
                .padding(.bottom, index == 0 ? 16 : 0)

                if index > 0 && index < Intent.allCases.count - 1 {
                    Theme.Palette.hairline.frame(height: 1)
                }
            }
        }
        .padding(.top, 22)
    }


    private func originals(_ person: Person) -> some View {
        let items = library.assets(for: person, source: .original)
        return VStack(alignment: .leading, spacing: 0) {
            QuietDivider()

            HStack {
                SectionLabel(text: L("Original recordings"))
                Spacer()
                Button(L("Add their voice")) { addingVoice = true }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.Palette.wine)
            }

            if items.isEmpty {
                SubText(text: L("No recordings yet")).padding(.top, 10)
            } else {
                ForEach(items) { asset in
                    AudioRow(asset: asset)
                }
            }
        }
    }


    /// Everything kept for this person, in one place. Book pages are excluded:
    /// they are kept automatically so they are never paid for twice, and
    /// counting them would drown the things the user actually chose to keep.
    private func savedLink(_ person: Person) -> some View {
        let memories = library.keptClips(for: person)
        return NavigationLink {
            // Not .recreated: the screen it opens is headed "Original
            // recordings and the new words you chose to save", and a
            // pre-set filter quietly hiding half of that is a lie in a
            // place this app cannot afford one.
            MemoriesView(personId: person.id)
        } label: {
            HStack {
                Text(L("Everything saved"))
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(memories.isEmpty ? L("Nothing saved yet")
                                      : Counts.savedClips(memories.count))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
            .foregroundStyle(Theme.Palette.wine)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: Theme.Metric.buttonHeight)
            .background(
                RoundedRectangle(cornerRadius: Theme.Metric.buttonRadius, style: .continuous)
                    .fill(Color(hex: 0xFFFAF4))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Metric.buttonRadius, style: .continuous)
                    .stroke(Theme.Palette.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.top, 22)
    }

    /// Delete at the provider first, then here.
    ///
    /// The order is the whole point. The voice id lives only in this app's
    /// index, so removing the person first would leave a clone of a real
    /// person's voice sitting on someone else's server with nothing left that
    /// knows its name. If the provider call fails we stop and say so, and the
    /// person is still here to try again with.
    @MainActor
    private func remove(_ person: Person) async {
        deleteProblem = nil

        guard let voiceId = person.voiceId else {
            library.delete(person)
            // Without this the screen stays up with `person` gone, showing an
            // empty state under an app bar, and the only way out is an edge
            // swipe.
            dismiss()
            return
        }

        isDeleting = true
        do {
            try await AppConfig.voiceService().deleteVoice(voiceId: voiceId)
        } catch is ConsentMissing {
            isDeleting = false
            deleteProblem = AppConfig.unavailableMessage
            return
        } catch {
            isDeleting = false
            deleteProblem = (error as? VoiceServiceError)?.errorDescription
                ?? L("The voice could not be removed from the voice service.")
            return
        }
        isDeleting = false
        library.delete(person)
        dismiss()
    }

    private func deleteRow(_ person: Person) -> some View {
        VStack(spacing: 0) {
            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Text(L("Remove this person"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .underline()
                    .frame(maxWidth: .infinity, minHeight: Theme.Metric.touchTarget)
            }
            .confirmationDialog(L("Delete this person?"),
                                isPresented: $confirmingDelete,
                                titleVisibility: .visible) {
                Button(L("Delete permanently"), role: .destructive) {
                    Task { await remove(person) }
                }
                Button(L("Cancel"), role: .cancel) { }
            } message: {
                Text(L("This removes their profile, original recordings, saved clips and imported books from Jaddati.")
                     + "\n\n"
                     + (person.voiceId == nil
                        ? L("Nothing was ever sent to the voice service for this person.")
                        : L("The voice built for them is deleted from the voice service first. If that fails, nothing here is removed, so you can try again.")))
            }
            .disabled(isDeleting)

            if isDeleting {
                Text(L("Removing the voice from the voice service…"))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .padding(.top, Theme.Space.xs)
            }

            // Inline, not a second dialog. A confirmationDialog raised while
            // the first one is still dismissing is dropped by UIKit, and the
            // paths that get here most often — consent declined, no key —
            // fail without ever suspending, so they land in exactly that
            // window and the person would see nothing happen at all.
            if let deleteProblem {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    ErrorNote(message: deleteProblem + "\n\n"
                              + L("The voice will stay at the voice service and this app will no longer know its name, so it cannot be removed from here later."))
                    Button(L("Remove from this phone")) {
                        library.delete(person)
                        dismiss()
                    }
                    .buttonStyle(QuietButtonStyle())
                    Button(L("Keep for now")) { self.deleteProblem = nil }
                        .buttonStyle(QuietButtonStyle())
                }
                .padding(.top, Theme.Space.xs)
            }
        }
        .padding(.top, 18)
    }


}

/// One playable item, used in every list. It always carries its own labels:
/// whose voice, and what the words are.
struct AudioRow: View {
    let asset: AudioAsset
    /// When set, the row shows a disclosure control that opens the full player.
    /// Passed as a closure rather than wrapping the row in a NavigationLink,
    /// because a Button inside a link label loses its taps to the link.
    var onOpen: (() -> Void)? = nil

    @EnvironmentObject private var library: Library
    @EnvironmentObject private var player: AudioPlayer

    var body: some View {
        let present = library.fileExists(for: asset)   // one stat per pass, not three
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    guard present else { return }
                    player.play(url: library.url(for: asset), assetId: asset.id)
                } label: {
                    Image(systemName: player.isPlaying(assetId: asset.id) ? "pause.fill" : "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.Palette.wine)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Theme.Palette.sunk))
                        .overlay(Circle().stroke(Theme.Palette.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(!present)

                VStack(alignment: .leading, spacing: 5) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) { badges }
                        VStack(alignment: .leading, spacing: 5) { badges }
                    }

                    if !asset.text.isEmpty {
                        BidiText(value: asset.text,
                                 font: .system(size: 15, weight: .semibold),
                                 colour: Theme.Palette.ink,
                                 lineLimit: 2)
                    } else {
                        Text(asset.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.Palette.ink)
                    }

                    // A row at half opacity with a dead play button is
                    // indistinguishable from a broken app unless it says why.
                    if !present {
                        Text(L("Audio file missing"))
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Palette.danger)
                    } else if asset.durationSeconds > 0 {
                        Text(Counts.duration(asset.durationSeconds))
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Palette.inkSoft)
                    }
                }

                Spacer(minLength: 0)

                if let onOpen {
                    Button(action: onOpen) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x958578))
                            .frame(width: 44, height: 44)      // full touch target
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("View all"))
                }
            }
            .padding(.vertical, 15)

            Theme.Palette.hairline.frame(height: 1)
        }
        .opacity(present ? 1 : 0.5)
    }

    @ViewBuilder private var badges: some View {
        SourceBadge(isGenerated: asset.isGenerated)
        if asset.isGenerated, let content = asset.contentProvenance {
            ContentBadge(provenance: content)
        }
    }
}
