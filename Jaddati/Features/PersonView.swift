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
    @State private var photoPick: PhotosPickerItem?
    @State private var checkingAvailability = false
    @State private var availabilityNote: String?

    private var person: Person? { library.person(withId: personId) }

    var body: some View {
        VStack(spacing: 0) {
            AppBar(title: person?.name ?? L("Jaddati"), trailing: gear)

            if let person {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        profile(person)

                        if !AppConfig.isConfigured {
                            notConnectedNote.padding(.top, 21)
                        }

                        primaryAction(person)

                        // No voice means nothing to put in them, and an empty
                        // room you have to open to discover is empty is the
                        // kind of thing that made this screen tiring.
                        if person.hasVoice { cards(person) }
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
        // Centred, because this screen now has one thing to say and one thing
        // to offer. Left-aligned was right when it was a header sitting above
        // a list of seven rows; it is not a header any more. Remove photo
        // moved to Setup with everything else done once.
        return VStack(spacing: 7) {
            PhotosPicker(selection: $photoPick, matching: .images, photoLibrary: .shared()) {
                ZStack(alignment: .bottomTrailing) {
                    PersonAvatar(name: person.name, imageURL: photo, size: 104)
                    Image(systemName: photo == nil ? "plus" : "pencil")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.Palette.paper)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Theme.Palette.wine))
                        .overlay(Circle().stroke(Theme.Palette.paper, lineWidth: 2))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(photo == nil ? L("Add photo") : L("Change photo"))

            BidiText(value: person.name,
                     font: Theme.Font.display(31),
                     colour: Theme.Palette.ink)
            if !person.relationship.isEmpty {
                BidiText(value: person.relationship,
                         font: .system(size: 14),
                         colour: Theme.Palette.inkSoft)
            }
            voiceTag(person)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 22)
    }

    /// Setup is a gear, not a row on this screen. Everything behind it is done
    /// once; everything on this screen is done again and again.
    private var gear: AnyView? {
        guard let person else { return nil }
        return AnyView(
            NavigationLink {
                SetupView(personId: person.id)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.Palette.ink)
                    .frame(width: Theme.Metric.touchTarget, height: Theme.Metric.touchTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(L("Setup"))
        )
    }

    /// One button, and which button it is depends entirely on where this
    /// person is.
    ///
    /// This screen used to show all four voice states' worth of copy AND seven
    /// things to do, and a first-time user had to read the lot to work out
    /// which of it applied to them. There is only ever one sensible next move
    /// here, so it is the only one offered.
    @ViewBuilder
    private func primaryAction(_ person: Person) -> some View {
        VStack(spacing: 0) {
            if person.voiceIsUnavailableHere {
                Button(L("Create a real voice")) { addingVoice = true }
                    .buttonStyle(PrimaryButtonStyle())
                actionNote(L("Created in offline test mode. This is not a usable voice."))
            } else if person.voicePendingVerification {
                Button(checkingAvailability ? L("Checking…") : L("Check if it is ready")) {
                    Task { await checkAvailability() }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canCheckAvailability)
                actionNote(L("The voice has been created, but the service has not made it available yet."))
                if let availabilityNote {
                    Text(availabilityNote)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.danger)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
            } else if !person.hasVoice {
                Button(L("Add their voice")) { addingVoice = true }
                    .buttonStyle(PrimaryButtonStyle())
                actionNote(L("About a minute. One voice. A quiet room."))
                // Recording someone still alive is the one other thing worth
                // offering here, and it matters MOST before a voice exists —
                // which is exactly when it used to sit furthest down the page.
                NavigationLink {
                    CaptureView(personId: person.id)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "mic").font(.system(size: 13))
                        Text(L("They are still here? Record them now"))
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(Theme.Palette.wineInk)
                    .frame(maxWidth: .infinity, minHeight: Theme.Metric.touchTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            } else {
                NavigationLink {
                    CreateView(personId: person.id, intent: .saySomething)
                } label: {
                    Text(L("Say something"))
                }
                .buttonStyle(PrimaryButtonStyle())
                actionNote(L("Type the words. Hear them in their voice."))
            }
        }
        .padding(.top, 20)
    }

    private func actionNote(_ words: String) -> some View {
        Text(words)
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Palette.inkSoft)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
    }

    /// Three doors, not seven rows. Each says how much is behind it, so nobody
    /// opens an empty room to find out it is empty.
    private func cards(_ person: Person) -> some View {
        let kept = library.keptClips(for: person).count
        let bookCount = library.books(for: person).count
        let letters = library.letters(for: person)
        let due = letters.filter(\.isDue).count
        let sealedCount = letters.filter(\.isSealed).count

        return HStack(alignment: .top, spacing: 9) {
            card(icon: "tray",
                 title: L("Saved"),
                 note: kept > 0 ? Counts.savedClips(kept) : L("Nothing saved yet"),
                 badge: 0) { AnyView(MemoriesView(personId: person.id)) }

            card(icon: "book",
                 title: L("Books"),
                 note: bookCount > 0 ? Counts.books(bookCount) : L("Bring them a text"),
                 badge: 0) { AnyView(BooksView(personId: person.id)) }

            card(icon: due > 0 ? "lock.open" : "lock",
                 title: L("Letters"),
                 note: due > 0 ? L("Waiting for you")
                     : sealedCount > 0 ? Counts.sealed(sealedCount) : L("For a day you choose"),
                 badge: due) { AnyView(LettersView(personId: person.id)) }
        }
        .padding(.top, 26)
    }

    private func card(icon: String, title: String, note: String, badge: Int,
                      destination: @escaping () -> AnyView) -> some View {
        NavigationLink { destination() } label: {
            VStack(alignment: .leading, spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.Palette.wineInk)
                    .overlay(alignment: .topTrailing) {
                        if badge > 0 {
                            Text(Counts.number(badge))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Theme.Palette.paper)
                                .frame(minWidth: 17, minHeight: 17)
                                .background(Circle().fill(Theme.Palette.danger))
                                .offset(x: 12, y: -6)
                        }
                    }
                    .padding(.bottom, 2)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .padding(.horizontal, 11)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: Theme.Metric.cardRadius)
                    .fill(Theme.Palette.card)
                    .overlay(RoundedRectangle(cornerRadius: Theme.Metric.cardRadius)
                        .stroke(Theme.Palette.hairline, lineWidth: 1))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                        .foregroundStyle(Theme.Palette.wineInk)
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
