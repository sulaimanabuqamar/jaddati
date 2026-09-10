import SwiftUI

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

                        let memories = library.assets(for: person, source: .generated)
                            .filter { $0.isSaved }
                        if !memories.isEmpty {
                            NavigationLink {
                                MemoriesView(personId: person.id, filter: .generated)
                            } label: {
                                Panel {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Saved memories")
                                                .font(Theme.Font.label)
                                                .foregroundStyle(Theme.Palette.ink)
                                            Text("\(memories.count) kept")
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
    }

    // MARK: Pieces

    private func header(_ person: Person) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(person.name)
                .font(Theme.Font.display(38))
                .foregroundStyle(Theme.Palette.forest)
            if !person.relationship.isEmpty {
                Text(person.relationship)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
            if person.hasVoice {
                HStack(spacing: 6) {
                    Circle().fill(Theme.Palette.bronze).frame(width: 6, height: 6)
                    Text("Voice ready")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.bronze)
                }
                .padding(.top, 2)
            }
        }
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
                Button("Create the real voice") { addingVoice = true }
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
                Text("Voice created, not yet usable")
                    .font(Theme.Font.heading)
                    .foregroundStyle(Theme.Palette.ink)
                Text("The voice service accepted the recording but is holding the voice for verification. It cannot speak until that clears. Check the voice in your ElevenLabs account.")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var noVoiceYet: some View {
        Panel {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("No voice yet")
                    .font(Theme.Font.heading)
                    .foregroundStyle(Theme.Palette.ink)
                Text("Add a recording of about a minute — a voice note, an old video's audio — and Jaddati can speak new words in that voice.")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Add their voice") { addingVoice = true }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 2)
            }
        }
    }

    private func intents(_ person: Person) -> some View {
        VStack(spacing: Theme.Space.s) {
            ForEach(Intent.allCases, id: \.self) { intent in
                NavigationLink {
                    CreateView(personId: person.id, intent: intent)
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
                Text("Their own voice")
                    .font(Theme.Font.heading)
                    .foregroundStyle(Theme.Palette.ink)
                Spacer()
                if person.hasVoice || person.voicePendingVerification {
                    Button("Replace") { addingVoice = true }
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.forest)
                }
            }

            if items.isEmpty {
                Text("Nothing here yet.")
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
                Text("Delete \(person.name) and all their audio")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.danger)
            }
            .confirmationDialog("Delete \(person.name)?",
                                isPresented: $confirmingDelete,
                                titleVisibility: .visible) {
                Button("Delete everything on this phone", role: .destructive) {
                    library.delete(person)
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This removes the profile, the original recordings and every generated memory from this phone. The voice created at the provider is not deleted by this action — remove it in your ElevenLabs account.")
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
                        Text(asset.text)
                            .font(Theme.Font.body)
                            .foregroundStyle(Theme.Palette.ink)
                            .lineLimit(2)
                    } else {
                        Text(asset.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(Theme.Font.body)
                            .foregroundStyle(Theme.Palette.ink)
                    }
                    SourceBadge(isGenerated: asset.isGenerated)
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
                    .accessibilityLabel("Open")
                }
            }
        }
        .opacity(present ? 1 : 0.5)
    }
}
