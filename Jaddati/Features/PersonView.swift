import SwiftUI
import PhotosUI

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
    @State private var confirmingDelete = false
    @State private var photoPick: PhotosPickerItem?

    private var person: Person? { library.person(withId: personId) }

    var body: some View {
        VStack(spacing: 0) {
            AppBar(title: L("A family archive"))

            if let person {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        profile(person)

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
                .accessibilityLabel(photo == nil ? L("Add a person") : L("Change recording"))

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
    @ViewBuilder private func voiceTag(_ person: Person) -> some View {
        let words: String
        let tint: Color
        if person.voiceIsUnavailableHere { words = L("Test voice only"); tint = Theme.Palette.danger }
        else if person.hasVoice { words = L("Recreated voice ready"); tint = Theme.Palette.wine }
        else if person.voicePendingVerification { words = L("Voice is being prepared"); tint = Theme.Palette.amber }
        else { words = L("No recreated voice yet"); tint = Theme.Palette.inkSoft }

        Text(words.uppercased())
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


    /// A library photo is many times larger than a 78-point circle needs, and
    /// `PersonAvatar` re-reads the file from disk on every render. Shrink once,
    /// on import, so that read stays cheap.
    private static func downscale(_ data: Data, to maxSide: CGFloat = 600) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        guard longest > maxSide else { return image.jpegData(compressionQuality: 0.85) }
        let scale = maxSide / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let shrunk = UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return shrunk.jpegData(compressionQuality: 0.85)
    }

    /// This voice was minted by the offline test mode and does not exist at the
    /// provider. Before this state existed the profile read "Voice ready", all
    /// four experiences unlocked, and every generation failed on an invalid id
    /// with no way to recover from the screen you were on.
    private var placeholderVoice: some View {
        Panel {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("This voice was made in test mode")
                    .font(Theme.Font.heading)
                    .foregroundStyle(Theme.Palette.ink)
                Text("It only works while offline test mode is on. To speak for real, add the recording again now that the voice service is connected — it takes a few seconds.")
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

                if index > 0 && index < Intent.allCases.count - 1 {
                    Theme.Palette.hairline.frame(height: 1)
                }
            }
        }
        .padding(.top, 4)
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
    @ViewBuilder private func savedLink(_ person: Person) -> some View {
        let memories = library.assets(for: person, source: .generated)
            .filter { $0.isSaved && $0.intentRaw != Intent.readBook.rawValue }
        if !memories.isEmpty {
            NavigationLink {
                MemoriesView(personId: person.id, filter: .recreated)
            } label: {
                HStack {
                    Text(L("Everything saved"))
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text(Counts.savedClips(memories.count))
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
    }

    private func deleteRow(_ person: Person) -> some View {
        VStack(spacing: 0) {
            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Text(L("Manage voice"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .underline()
                    .frame(maxWidth: .infinity, minHeight: Theme.Metric.touchTarget)
            }
            .confirmationDialog(L("Delete this person?"),
                                isPresented: $confirmingDelete,
                                titleVisibility: .visible) {
                Button(L("Delete permanently"), role: .destructive) {
                    library.delete(person)
                }
                Button(L("Cancel"), role: .cancel) { }
            } message: {
                Text(L("This removes their profile, original recordings, and saved clips from Jaddati.")
                     + "\n\n"
                     + L("Deleting from Jaddati does not confirm deletion by the voice service."))
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

                    if asset.durationSeconds > 0 {
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
