import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

/// Import a recording and build a voice from it.
///
/// The consent step is not decoration. The provider requires the uploader to
/// hold the rights to the voice, and this product is about someone who cannot
/// be asked. The wording says exactly that, and the confirmation is stored with
/// the profile.
struct AddVoiceView: View {
    let personId: UUID

    @EnvironmentObject private var library: Library
    @Environment(\.dismiss) private var dismiss

    @State private var pickedURL: URL?
    @State private var pickedName: String = ""
    @State private var pickedDuration: Double = 0
    @State private var showingPicker = false
    @State private var consented = false
    @State private var isWorking = false
    @State private var errorText: String?

    private var person: Person? { library.person(withId: personId) }

    private var canSubmit: Bool {
        pickedURL != nil && consented && !isWorking
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Palette.ivory.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        Text(person?.hasVoice == true ? "Add another recording" : "Add their voice")
                            .font(Theme.Font.title)
                            .foregroundStyle(Theme.Palette.ink)

                        filePanel
                        guidance
                        consentPanel

                        if let errorText {
                            ErrorNote(message: errorText) { self.errorText = nil }
                        }

                        Button(isWorking ? "Building the voice…" : "Create the voice") {
                            Task { await createVoice() }
                        }
                        .buttonStyle(PrimaryButtonStyle(enabled: canSubmit))
                        .disabled(!canSubmit)

                        if isWorking {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("This usually takes a few seconds. Keep the app open.")
                                    .font(Theme.Font.caption)
                                    .foregroundStyle(Theme.Palette.inkSoft)
                            }
                        }
                    }
                    .padding(Theme.Space.m)
                    .padding(.bottom, Theme.Space.xl)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isWorking)
                }
            }
            .fileImporter(isPresented: $showingPicker,
                          allowedContentTypes: [.audio, .mpeg4Audio, .mp3, .wav],
                          allowsMultipleSelection: false) { result in
                handlePick(result)
            }
        }
        .interactiveDismissDisabled(isWorking)
    }

    // MARK: Panels

    private var filePanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                if pickedURL != nil {
                    HStack(spacing: Theme.Space.s) {
                        Image(systemName: "waveform")
                            .foregroundStyle(Theme.Palette.bronze)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pickedName)
                                .font(Theme.Font.label)
                                .foregroundStyle(Theme.Palette.ink)
                                .lineLimit(1)
                            Text(durationLabel)
                                .font(Theme.Font.caption)
                                .foregroundStyle(durationIsShort ? Theme.Palette.danger
                                                                 : Theme.Palette.inkSoft)
                        }
                        Spacer(minLength: 0)
                        Button("Change") { showingPicker = true }
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Palette.forest)
                    }
                } else {
                    Button {
                        showingPicker = true
                    } label: {
                        HStack(spacing: Theme.Space.s) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 20))
                                .foregroundStyle(Theme.Palette.forest)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Choose a recording")
                                    .font(Theme.Font.label)
                                    .foregroundStyle(Theme.Palette.ink)
                                Text("From Files, iCloud Drive, or anywhere on this phone")
                                    .font(Theme.Font.caption)
                                    .foregroundStyle(Theme.Palette.inkSoft)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var guidance: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What works best")
                .font(Theme.Font.label)
                .foregroundStyle(Theme.Palette.ink)
            Text("About a minute of them talking, one voice only, as little background noise as possible. Short clips and noisy rooms make a thinner result.")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var consentPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Toggle(isOn: $consented) {
                    Text("I have the right to use this recording and to have this voice recreated.")
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .tint(Theme.Palette.forest)

                Text("The recording is uploaded to ElevenLabs, which creates the voice and stores it under this app's account. It does not stay on this phone only. If the person has died, the right to use their voice sits with their family or estate, and rules differ by country — this app cannot check that for you.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Behaviour

    private var durationLabel: String {
        guard pickedDuration > 0 else { return "Length unknown" }
        let seconds = Int(pickedDuration.rounded())
        let text = seconds >= 60 ? "\(seconds / 60)m \(seconds % 60)s" : "\(seconds)s"
        return durationIsShort ? "\(text) — shorter than recommended" : text
    }

    private var durationIsShort: Bool { pickedDuration > 0 && pickedDuration < 45 }

    private func handlePick(_ result: Result<[URL], Error>) {
        switch result {
        case .failure:
            errorText = "That file could not be opened."
        case .success(let urls):
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            // Copy out immediately — the picker's URL is not valid for long.
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(url.pathExtension.isEmpty ? "m4a" : url.pathExtension)
            do {
                if FileManager.default.fileExists(atPath: temp.path) {
                    try FileManager.default.removeItem(at: temp)
                }
                try FileManager.default.copyItem(at: url, to: temp)
            } catch {
                errorText = "That file could not be read from its location."
                return
            }

            pickedURL = temp
            pickedName = url.lastPathComponent
            pickedDuration = (try? AVAudioPlayer(contentsOf: temp))?.duration ?? 0
            errorText = nil
        }
    }

    private func createVoice() async {
        guard let person, let sampleURL = pickedURL else { return }
        isWorking = true
        errorText = nil

        let service: VoiceService = ElevenLabsClient()
        do {
            let voiceId = try await service.createVoice(name: "Jaddati — \(person.name)",
                                                        sampleURL: sampleURL)

            // Keep the original. The archive must always be able to show what
            // the person actually sounded like, next to anything generated.
            if let data = try? Data(contentsOf: sampleURL) {
                library.storeAudio(data: data,
                                   for: person,
                                   source: .original,
                                   text: "",
                                   duration: pickedDuration,
                                   fileExtension: sampleURL.pathExtension.isEmpty
                                       ? "m4a" : sampleURL.pathExtension)
            }

            var updated = person
            updated.voiceId = voiceId
            updated.voiceCreatedAt = Date()
            updated.consentConfirmedAt = Date()
            library.update(updated)

            try? FileManager.default.removeItem(at: sampleURL)
            isWorking = false
            dismiss()
        } catch {
            isWorking = false
            errorText = (error as? VoiceServiceError)?.errorDescription
                ?? "The voice could not be created. \(error.localizedDescription)"
        }
    }
}
