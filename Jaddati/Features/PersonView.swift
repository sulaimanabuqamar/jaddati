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
        ZStack {
            Theme.Palette.ivory.ignoresSafeArea()

            if let person {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        header(person)

                        if person.hasVoice {
                            intents(person)
                        } else if person.voiceIsUnavailableHere {
                            placeholderVoice
                        } else if person.voicePendingVerification {
                            pendingVerification
                        } else {
                            noVoiceYet
                        }

                        originals(person)

                        // Book pages are kept automatically so they are never
                        // paid for twice; counting them here would drown the
                        // things the user actually chose to keep.
                        let memories = library.assets(for: person, source: .generated)
                            .filter { $0.isSaved && $0.intentRaw != Intent.readBook.rawValue }
                        if !memories.isEmpty {
                            NavigationLink {
                                MemoriesView(personId: person.id, filter: .recreated)
                            } label: {
                                Panel {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(L("Everything saved"))
                                                .font(Theme.Font.label)
                                                .foregroundStyle(Theme.Palette.ink)
                                            Text(Counts.savedClips(memories.count))
                                                .font(Theme.Font.caption)
                                                .foregroundStyle(Theme.Palette.inkSoft)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(Theme.Palette.hairline)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }

                        deleteRow(person)
                    }
                    .padding(Theme.Space.m)
                    .padding(.bottom, Theme.Space.xl)
                }
            } else {
                EmptyHint(icon: "person.slash",
                          title: "Removed",
                          message: "This profile is no longer on the phone.")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
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

    private func header(_ person: Person) -> some View {
        let photo = library.photoURL(for: person)
        return HStack(alignment: .top, spacing: Theme.Space.s) {
            PhotosPicker(selection: $photoPick, matching: .images, photoLibrary: .shared()) {
                ZStack(alignment: .bottomTrailing) {
                    PersonAvatar(name: person.name, imageURL: photo, size: 78)
                    Image(systemName: photo == nil ? "plus" : "pencil")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.Palette.ivory)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Theme.Palette.forest))
                        .overlay(Circle().stroke(Theme.Palette.ivory, lineWidth: 2))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(photo == nil ? "Add a photo" : "Change photo")

            VStack(alignment: .leading, spacing: 6) {
                BidiText(value: person.name,
                         font: Theme.Font.display(34),
                         colour: Theme.Palette.forest)
                    .fixedSize(horizontal: false, vertical: true)
                if !person.relationship.isEmpty {
                    BidiText(value: person.relationship,
                             font: Theme.Font.body,
                             colour: Theme.Palette.inkSoft)
                }
                if person.hasVoice {
                    HStack(spacing: 6) {
                        Circle().fill(Theme.Palette.sage).frame(width: 6, height: 6)
                        Text(L("Recreated voice ready"))
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Palette.sage)
                    }
                    .padding(.top, 2)
                }
                if photo != nil {
                    Button("Remove photo") { library.removePhoto(for: person) }
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.inkSoft)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
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
        VStack(spacing: Theme.Space.s) {
            ForEach(Intent.allCases, id: \.self) { intent in
                NavigationLink {
                    // Books are a shelf, not a compose box.
                    if intent == .readBook {
                        BooksView(personId: person.id)
                    } else {
                        CreateView(personId: person.id, intent: intent)
                    }
                } label: {
                    Panel(padding: Theme.Space.s) {
                        HStack(spacing: Theme.Space.s) {
                            Image(systemName: intent.icon)
                                .font(.system(size: 17))
                                .foregroundStyle(Theme.Palette.bronze)
                                .frame(width: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(intent.title)
                                    .font(Theme.Font.label)
                                    .foregroundStyle(Theme.Palette.ink)
                                Text(intent.subtitle)
                                    .font(Theme.Font.caption)
                                    .foregroundStyle(Theme.Palette.inkSoft)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.Palette.hairline)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func originals(_ person: Person) -> some View {
        let items = library.assets(for: person, source: .original)
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack {
                Text(L("Original recordings"))
                    .font(Theme.Font.heading)
                    .foregroundStyle(Theme.Palette.ink)
                Spacer()
                if person.hasVoice || person.voicePendingVerification {
                    Button(L("Create a new voice version")) { addingVoice = true }
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.forest)
                }
            }

            if items.isEmpty {
                Text(L("No recordings yet"))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
            } else {
                ForEach(items) { asset in
                    AudioRow(asset: asset)
                }
            }
        }
        .padding(.top, Theme.Space.xs)
    }

    private func deleteRow(_ person: Person) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Text(L("Delete person and audio"))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.danger)
            }
            .confirmationDialog(L("Delete this person?"),
                                isPresented: $confirmingDelete,
                                titleVisibility: .visible) {
                Button(L("Delete permanently"), role: .destructive) {
                    library.delete(person)
                }
                Button(L("Cancel"), role: .cancel) { }
            } message: {
                Text(L("This removes their profile, original recordings, and saved clips from Jaddati.") + "\n\n" + L("Deleting from Jaddati does not confirm deletion by the voice service."))
            }
        }
        .padding(.top, Theme.Space.m)
    }
}

/// A single playable item, used in every list. Always carries its source badge.
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
        return Panel(padding: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                Button {
                    guard present else { return }
                    player.play(url: library.url(for: asset), assetId: asset.id)
                } label: {
                    Image(systemName: player.isPlaying(assetId: asset.id) ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.Palette.ivory)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Theme.Palette.forest))
                }
                .buttonStyle(.plain)
                .disabled(!present)

                VStack(alignment: .leading, spacing: 5) {
                    if !asset.text.isEmpty {
                        // The clip's own words follow the clip's own direction,
                        // whichever way the interface happens to be facing.
                        BidiText(value: asset.text,
                                 font: Theme.Font.body,
                                 colour: Theme.Palette.ink,
                                 lineLimit: 2)
                    } else {
                        Text(asset.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(Theme.Font.body)
                            .foregroundStyle(Theme.Palette.ink)
                    }

                    // Both labels sit in the row, so an invented story is
                    // identifiable without opening it. They wrap rather than
                    // truncate: a provenance label that runs out of room and
                    // disappears is the one case that must not happen.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) { badges }
                        VStack(alignment: .leading, spacing: 5) { badges }
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
                            .foregroundStyle(Theme.Palette.inkSoft)
                            .frame(width: 44, height: 44)      // full touch target
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("View all"))
                }
            }
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
