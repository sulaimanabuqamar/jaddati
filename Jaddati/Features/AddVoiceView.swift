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
    /// False when the selection points at a file the library owns. Deleting one
    /// of those on dismiss would destroy the person's original recording.
    @State private var pickedIsTemporary = true
    @State private var pickedName: String = ""
    @State private var pickedDuration: Double = 0
    @State private var showingPicker = false
    @State private var consented = false
    @State private var isWorking = false
    @State private var errorText: String?
    /// False for messages that report a completed action. Retrying those would
    /// create a second voice at the provider, not fix anything.
    @State private var errorAllowsRetry = true
    @StateObject private var recorder = VoiceRecorder()
    @State private var recordProblem: String?

    private var person: Person? { library.person(withId: personId) }
    private var replacingExistingVoice: Bool {
        guard let person else { return false }
        return person.voiceId != nil
    }

    /// Too short to be worth uploading. The provider asks for about a minute;
    /// below twenty seconds it will either refuse or produce something thin,
    /// and either way a voice slot is spent finding that out.
    private var durationIsUnusable: Bool { pickedDuration > 0 && pickedDuration < 20 }
    private var durationIsShort: Bool { pickedDuration > 0 && pickedDuration < 45 }

    private var canSubmit: Bool {
        pickedURL != nil && consented && !isWorking
            && !durationIsUnusable && AppConfig.isConfigured
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Palette.ivory.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        Text(replacingExistingVoice ? "Replace their voice" : "Add their voice")
                            .font(Theme.Font.title)
                            .foregroundStyle(Theme.Palette.ink)

                        if !AppConfig.isConfigured {
                            ErrorNote(message: "Voices aren't set up on this build, so a voice can't be created yet.")
                        }

                        if replacingExistingVoice {
                            replacementWarning
                        }

                        filePanel
                        guidance
                        consentPanel

                        if let errorText {
                            if errorAllowsRetry {
                                ErrorNote(message: errorText) {
                                    self.errorText = nil
                                    Task { await createVoice() }
                                }
                            } else {
                                ErrorNote(message: errorText)
                            }
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
                    Button("Cancel") {
                        discardTempFile()
                        dismiss()
                    }
                    .disabled(isWorking)
                }
            }
            .fileImporter(isPresented: $showingPicker,
                          allowedContentTypes: [.audio, .mpeg4Audio, .mp3, .wav],
                          allowsMultipleSelection: false) { result in
                handlePick(result)
            }
        }
        .interactiveDismissDisabled(isWorking)
        .onDisappear {
            if recorder.isRecording { recorder.cancel() }
            discardTempFile()
        }
        .onChange(of: recorder.reachedLimit) { _, hit in
            if hit { stopRecording() }
        }
    }

    // MARK: Panels

    /// Each import creates a NEW voice at the provider and spends a slot. The
    /// old one is not deleted and keeps occupying the account's quota.
    private var replacementWarning: some View {
        Panel {
            VStack(alignment: .leading, spacing: 6) {
                Text("This creates a new voice")
                    .font(Theme.Font.label)
                    .foregroundStyle(Theme.Palette.ink)
                Text("The current voice is replaced for this person, but it is not deleted from your ElevenLabs account and keeps using one of its voice slots. Delete it there if you no longer want it.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

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
                        // Deselect rather than jumping straight to Files —
                        // that returns to the list, which offers both the
                        // already-saved recordings and the file picker.
                        Button("Change") { discardTempFile() }
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Palette.forest)
                    }
                } else {
                    if let person {
                        let stored = library.assets(for: person, source: .original)
                            .filter { library.fileExists(for: $0) }
                        if !stored.isEmpty {
                            Text("Already saved for \(person.name)")
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Palette.inkSoft)
                            ForEach(stored) { asset in
                                Button { use(asset) } label: {
                                    HStack(spacing: Theme.Space.s) {
                                        Image(systemName: "waveform")
                                            .foregroundStyle(Theme.Palette.bronze)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(asset.createdAt.formatted(date: .abbreviated,
                                                                           time: .shortened))
                                                .font(Theme.Font.body)
                                                .foregroundStyle(Theme.Palette.ink)
                                            Text(lengthLabel(asset.durationSeconds))
                                                .font(Theme.Font.caption)
                                                .foregroundStyle(Theme.Palette.inkSoft)
                                        }
                                        Spacer(minLength: 0)
                                        Text("Use")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(Theme.Palette.forest)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                            Divider().overlay(Theme.Palette.hairline)
                        }
                    }

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

                    Divider().overlay(Theme.Palette.hairline)

                    recordRow
                }
            }
        }
    }

    /// Recording straight into the app. The file it produces is handed to the
    /// same fields the file picker fills, so consent, validation and cleanup
    /// downstream are untouched.
    @ViewBuilder private var recordRow: some View {
        if recorder.isRecording {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                HStack(spacing: Theme.Space.s) {
                    // A bar that moves is the only honest sign the microphone is
                    // capturing. A timer alone counts up over silence just as happily.
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.Palette.ivorySunk)
                            Capsule()
                                .fill(Theme.Palette.bronze)
                                .frame(width: max(3, geometry.size.width * recorder.level))
                                .animation(.linear(duration: 0.1), value: recorder.level)
                        }
                    }
                    .frame(height: 8)

                    Text(recordTimeLabel)
                        .font(Theme.Font.caption.monospacedDigit())
                        .foregroundStyle(Theme.Palette.inkSoft)
                }

                Text(recorder.elapsed < 60
                     ? "Keep going \u{2014} about a minute is what the clone needs."
                     : "That is enough. Stop whenever you like.")
                    .font(.system(size: 11))
                    .foregroundStyle(recorder.elapsed < 60 ? Theme.Palette.danger
                                                           : Theme.Palette.inkSoft)

                HStack(spacing: Theme.Space.s) {
                    Button("Stop") { stopRecording() }
                        .buttonStyle(PrimaryButtonStyle())
                    Button("Discard") {
                        recorder.cancel()
                        recordProblem = nil
                    }
                    .buttonStyle(QuietButtonStyle())
                }
            }
        } else {
            Button {
                Task { await startRecording() }
            } label: {
                HStack(spacing: Theme.Space.s) {
                    Image(systemName: "mic.circle")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.Palette.forest)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Record now")
                            .font(Theme.Font.label)
                            .foregroundStyle(Theme.Palette.ink)
                        Text("Speak into this phone for about a minute")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Palette.inkSoft)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
        }

        if let recordProblem {
            Text(recordProblem)
                .font(.system(size: 11))
                .foregroundStyle(Theme.Palette.danger)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var recordTimeLabel: String {
        let seconds = Int(recorder.elapsed)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func startRecording() async {
        recordProblem = nil
        guard await recorder.requestPermission() else {
            recordProblem = recorder.permissionDenied
                ? "Microphone access is off for Jaddati. Turn it on in Settings."
                : "Microphone access was not granted."
            return
        }
        discardTempFile()
        recorder.start(purpose: .voiceSample)
        if let failure = recorder.error { recordProblem = failure }
    }

    private func stopRecording() {
        guard let result = recorder.stop() else { return }

        // The check that earns its keep. In the first version of this project a
        // recording library reported success and wrote a valid, empty file every
        // time. Cloning silence spends credits and fails in front of judges, so
        // refuse it here and say what was actually measured.
        guard result.capturedSound else {
            try? FileManager.default.removeItem(at: result.url)
            recordProblem = "That recording came out silent \u{2014} \(result.bytes) bytes, "
                + "peak \(Int(result.peakDecibels)) dB. Nothing reached the microphone. "
                + "Check nothing is covering it and try again."
            return
        }

        pickedURL = result.url
        pickedIsTemporary = true
        pickedName = "Recorded just now"
        pickedDuration = result.duration
        recordProblem = nil
        errorText = nil
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
        if durationIsUnusable { return "\(text) — too short to build a voice from" }
        if durationIsShort    { return "\(text) — shorter than recommended" }
        return text
    }

    /// Removes our own working copy — on cancel, on dismiss, and before
    /// replacing it with a different pick, so no abandoned import leaves a full
    /// recording behind in the temp directory. A file belonging to the library
    /// is only deselected, never deleted.
    private func discardTempFile() {
        guard let url = pickedURL else { return }
        if pickedIsTemporary {
            try? FileManager.default.removeItem(at: url)
        }
        pickedURL = nil
        pickedIsTemporary = true
        pickedName = ""
        pickedDuration = 0
    }

    /// Select a recording the library already holds. No copy is made, and the
    /// file is never deleted by this screen.
    private func use(_ asset: AudioAsset) {
        discardTempFile()
        let url = library.url(for: asset)
        pickedURL = url
        pickedIsTemporary = false
        pickedName = asset.text.isEmpty
            ? asset.createdAt.formatted(date: .abbreviated, time: .shortened)
            : asset.text
        pickedDuration = asset.durationSeconds > 0
            ? asset.durationSeconds
            : ((try? AVAudioPlayer(contentsOf: url))?.duration ?? 0)
        errorText = nil
    }

    private func lengthLabel(_ seconds: Double) -> String {
        guard seconds > 0 else { return "Length unknown" }
        let total = Int(seconds.rounded())
        return total >= 60 ? "\(total / 60)m \(total % 60)s" : "\(total)s"
    }

    private func handlePick(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            // SwiftUI reports the user tapping Cancel as a failure. Telling
            // them the file could not be opened when they chose not to open one
            // is just noise.
            if (error as? CocoaError)?.code == .userCancelled { return }
            // No retry: the fix is to choose a file, using the button directly
            // above this note. A "Try again" here would call createVoice() with
            // no file selected and do nothing at all.
            errorAllowsRetry = false
            errorText = "That file could not be opened."
        case .success(let urls):
            guard let url = urls.first else { return }
            discardTempFile()

            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            // Copy out immediately — the picker's URL is not valid for long.
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(url.pathExtension.isEmpty ? "m4a" : url.pathExtension)
            do {
                try FileManager.default.copyItem(at: url, to: temp)
            } catch {
                errorAllowsRetry = false
                errorText = "That file could not be read from its location."
                return
            }

            pickedURL = temp
            pickedIsTemporary = true
            pickedName = url.lastPathComponent
            pickedDuration = (try? AVAudioPlayer(contentsOf: temp))?.duration ?? 0
            errorText = nil
        }
    }

    private func createVoice() async {
        guard let person, let sampleURL = pickedURL, canSubmit else { return }
        isWorking = true
        errorText = nil
        errorAllowsRetry = true

        let service: VoiceService = AppConfig.voiceService()
        do {
            let voice = try await service.createVoice(name: "Jaddati — \(person.name)",
                                                      sampleURL: sampleURL)

            // Keep the original. The archive must always be able to show what
            // the person actually sounded like, next to anything generated —
            // so a failure here is reported, not swallowed.
            // Re-using a recording the library already holds must not add a
            // duplicate row pointing at the same audio.
            var originalStored = !pickedIsTemporary
            if pickedIsTemporary, let data = try? Data(contentsOf: sampleURL) {
                let ext = sampleURL.pathExtension.isEmpty ? "m4a" : sampleURL.pathExtension
                originalStored = library.storeAudio(data: data,
                                                    for: person,
                                                    source: .original,
                                                    duration: pickedDuration,
                                                    fileExtension: ext) != nil
            }

            var updated = person
            updated.voiceId = voice.id
            updated.voiceCreatedAt = Date()
            updated.voiceRequiresVerification = voice.requiresVerification
            updated.consentConfirmedAt = Date()
            library.update(updated)

            discardTempFile()
            isWorking = false

            if originalStored {
                dismiss()
            } else {
                errorAllowsRetry = false
                errorText = "The voice was created, but the original recording could not be saved to this phone. Import it again from the profile so it appears in the archive."
            }
        } catch {
            isWorking = false
            errorText = (error as? VoiceServiceError)?.errorDescription
                ?? "The voice could not be created. Try again."
        }
    }
}
