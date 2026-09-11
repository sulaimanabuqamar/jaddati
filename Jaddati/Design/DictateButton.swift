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
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Palette.ivorySunk)
                    Capsule()
                        .fill(Theme.Palette.bronze)
                        .frame(width: max(3, geometry.size.width * recorder.level))
                        .animation(.linear(duration: 0.1), value: recorder.level)
                }
            }
            .frame(height: 6)

            Text(timeLabel)
                .font(Theme.Font.caption.monospacedDigit())
                .foregroundStyle(Theme.Palette.inkSoft)

            Button(L("Pause")) { Task { await finishRecording() } }
                .buttonStyle(QuietButtonStyle())
        }
    }

    private var timeLabel: String {
        let seconds = Int(recorder.elapsed)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func beginRecording() async {
        problem = nil
        guard await recorder.requestPermission() else {
            problem = recorder.permissionDenied
                ? "Microphone access is off for Jaddati. Turn it on in Settings."
                : "Microphone access was not granted."
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
            problem = "Nothing was heard. Check the microphone and try again."
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
                ?? "That could not be written down. Try again."
        }
        isTranscribing = false
    }
}
