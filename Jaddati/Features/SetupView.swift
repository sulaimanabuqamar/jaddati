import SwiftUI

/// Everything you do once: give them a voice, record them while they are still
/// here to be recorded, hand the archive to the family, remove them.
///
/// All of this used to sit inline on the person screen, under the seven ways
/// of asking — so the rare and the daily competed for the same attention every
/// single time you opened someone. Behind the gear it is still one tap away
/// and no longer in the way of the thing you actually came to do.
struct SetupView: View {
    let personId: UUID

    @EnvironmentObject private var library: Library
    @EnvironmentObject private var consent: Consent
    @Environment(\.dismiss) private var dismiss

    @State private var addingVoice = false
    @State private var exported: URL?
    @State private var preparingArchive = false
    @State private var archiveNote: String?
    @State private var confirmingDelete = false
    @State private var isDeleting = false
    @State private var deleteProblem: String?

    private var person: Person? { library.person(withId: personId) }

    var body: some View {
        VStack(spacing: 0) {
            AppBar(title: L("Setup"))

            if let person {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionLabel(text: L("Their voice")).padding(.top, 16)

                        Button { addingVoice = true } label: {
                            FeatureRow(icon: "waveform",
                                       title: person.hasVoice ? L("Replace their voice") : L("Add their voice"),
                                       subtitle: L("About a minute. One voice. A quiet room."))
                        }
                        .buttonStyle(.plain)

                        capture(person)
                        handoff(person)
                        originals(person)
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
    }

    // MARK: Pieces

    /// Recording someone who is still alive is a different act from everything
    /// else on this screen, all of which is about someone who is not — and it
    /// is most useful BEFORE a voice exists, which is exactly when the
    /// experience list is hidden. So it renders on its own, either way.
    /// The voice lives at the voice service, not on this phone, so handing
    /// another family member the identifier lets them speak in it immediately —
    /// without paying to clone her twice or taking a second voice slot for the
    /// same person.
    private func handoff(_ person: Person) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Theme.Palette.hairline.frame(height: 1).padding(.bottom, 16)
            Text(L("One voice, the whole family"))
                .font(Theme.Font.label)
                .foregroundStyle(Theme.Palette.ink)
            Text(L("Make a file another family member can open on their own phone. It carries this person, your notes, anything still sealed, and the recreated voice itself — so they can hear them straight away without making the voice a second time."))
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            Text(L("Clips already created are not included. They can be made again on the other phone."))
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            // Bound to a different name on purpose. `if let exported` shadows the
            // @State with an unwrapped `let URL`, so clearing it inside this
            // branch assigns to the constant rather than to the state — which is
            // exactly the pair of errors the compiler gave.
            if let archiveFile = exported {
                ShareLink(item: archiveFile) {
                    Text(L("Give this to the family"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(QuietButtonStyle())
                // Seal a letter or add a memory after making the file and the
                // family would receive the version from before it. Making a new
                // one has to stay reachable.
                Button(L("Make it again, with the latest")) {
                    exported = nil
                    archiveNote = nil
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Palette.wineInk)
                .frame(minHeight: Theme.Metric.touchTarget, alignment: .leading)
            } else {
                Button(preparingArchive ? L("Preparing…") : L("Give this to the family")) {
                    Task { await prepareArchive(for: person) }
                }
                .buttonStyle(QuietButtonStyle())
                .disabled(preparingArchive)
            }

            if let archiveNote {
                Text(archiveNote)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
        }
        .padding(.top, 18)
    }

    /// Off the main thread: this reads every original recording, base64s it and
    /// writes the result, which on a real archive is seconds of work. Run inline
    /// it froze the UI and SwiftUI coalesced the state away, so "Preparing…"
    /// never appeared at all.
    ///
    /// @MainActor is load-bearing, not decoration: SE-0338 means a nonisolated
    /// async method does NOT inherit its caller's actor, so every @State write
    /// below would land off the main thread without it.
    @MainActor
    private func prepareArchive(for person: Person) async {
        preparingArchive = true
        archiveNote = nil
        let snapshot = person
        do {
            let result = try await Task.detached(priority: .userInitiated) { [library] in
                try Archive.export(person: snapshot, library: library)
            }.value
            exported = result.url
            archiveNote = result.unreadable > 0
                ? L("Some recordings could not be read from this phone and were left out.")
                : result.tooLarge > 0
                  ? L("Sent without some recordings — the file would have been too large.")
                  : result.carried > 0 ? L("Ready to send.")
                    : L("Ready to send. No original recordings were included.")
        } catch {
            archiveNote = error.localizedDescription
        }
        preparingArchive = false
    }

    private func capture(_ person: Person) -> some View {
        VStack(spacing: 0) {
            Theme.Palette.hairline.frame(height: 1)
            NavigationLink {
                CaptureView(personId: person.id)
            } label: {
                FeatureRow(icon: "mic",
                           title: L("Recorded before it is needed"),
                           subtitle: L("Ask for the recording while they are still here to give it"))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 18)
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
                    .foregroundStyle(Theme.Palette.wineInk)
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

        // A voice that arrived in a family archive belongs to everyone holding
        // that archive. Removing this copy must not reach the service.
        guard let voiceId = person.voiceId, person.voiceIsShared != true else {
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
                     + (person.voiceIsShared == true
                        ? L("This person came from another family member's phone, so the voice is shared. It is left alone at the voice service — removing it here would take it from everyone who has them.")
                        : person.voiceId == nil
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
