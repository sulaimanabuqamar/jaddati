import SwiftUI

/// Speak instead of typing. Drops into any composer: it owns its own recorder,
/// appends what it hears to the binding it was given, and never clears what is
/// already there.
struct DictateButton: View {
    @Binding var text: String
    var prompt: String = L("Speak instead")

    @StateObject private var recorder = VoiceRecorder()
    @State private var isTranscribing = false
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if recorder.isRecording {
                listening
            } else {
                Button {
                    Task { await beginRecording() }
                } label: {
                    Label(isTranscribing ? L("Writing it down…") : prompt,
                          systemImage: "mic.fill")
                        .font(Theme.Font.caption)
                }
                .buttonStyle(QuietButtonStyle())
                .disabled(isTranscribing)
            }

            if let problem {
                Text(problem)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.bronze)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onDisappear { if recorder.isRecording { recorder.cancel() } }
        .onChange(of: recorder.reachedLimit) { _, hit in
            if hit { Task { await finishRecording() } }
        }
    }

    private var listening: some View {
        HStack(spacing: Theme.Space.s) {
            // A bar that moves is the only honest signal that the microphone is
            // actually capturing. A spinner would look identical over silence.
            LiveMeter(meter: recorder.meter, height: 6)

            Button(L("Pause")) { Task { await finishRecording() } }
                .buttonStyle(QuietButtonStyle())
        }
    }

    private func beginRecording() async {
        problem = nil
        guard await recorder.requestPermission() else {
            problem = recorder.permissionDenied
                ? L("Microphone access is off. Turn it on in Settings.")
                : L("Microphone access was not granted.")
            return
        }
        guard AppConfig.isTranscriptionConfigured else {
            problem = TranscriptionError.notConfigured.errorDescription
            return
        }
        recorder.start(purpose: .dictation)
        if let failure = recorder.error { problem = failure }
    }

    private func finishRecording() async {
        guard let result = recorder.stop() else { return }
        defer { try? FileManager.default.removeItem(at: result.url) }

        guard result.capturedSound else {
            problem = L("Nothing was heard. Check the microphone and try again.")
            return
        }

        isTranscribing = true
        do {
            let heard = try await AppConfig.transcriber().transcribe(fileURL: result.url)
            let existing = text.trimmingCharacters(in: .whitespacesAndNewlines)
            text = existing.isEmpty ? heard : existing + " " + heard
            problem = nil
        } catch {
            problem = (error as? TranscriptionError)?.errorDescription
                ?? L("That could not be written down. Try again.")
        }
        isTranscribing = false
    }
}

/// The moving bar and the clock. The only thing on either screen that has to
/// redraw while the microphone is open, and so the only thing that observes the
/// recorder's live numbers.
struct LiveMeter: View {
    @ObservedObject var meter: RecordingMeter
    var height: CGFloat = 8

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Palette.ivorySunk)
                    Capsule()
                        .fill(Theme.Palette.bronze)
                        .frame(width: max(3, geometry.size.width * meter.level))
                        .animation(.linear(duration: 0.1), value: meter.level)
                }
            }
            .frame(height: height)

            Text(clock)
                .font(Theme.Font.caption.monospacedDigit())
                .foregroundStyle(Theme.Palette.inkSoft)
        }
    }

    private var clock: String {
        let seconds = Int(meter.elapsed)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// The line under the bar on the voice screen, for the same reason.
struct RecordingHint: View {
    @ObservedObject var meter: RecordingMeter

    var body: some View {
        Text(meter.elapsed < 60
             ? L("Keep going — about a minute is what the voice needs.")
             : L("That is enough. Stop whenever you like."))
            .font(.system(size: 11))
            // Was danger red for the normal case, so a recording going exactly
            // to plan looked like it was failing.
            .foregroundStyle(meter.elapsed < 60 ? Theme.Palette.amber
                                                : Theme.Palette.sage)
    }
}
