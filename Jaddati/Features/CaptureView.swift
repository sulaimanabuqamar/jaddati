import SwiftUI

/// Recorded before it is needed.
///
/// The hard part was never the recording. It is knowing what to ask for — so
/// this asks for six specific things rather than "record a voice sample". Each
/// is worth having whatever happens, and together they cover what a clone
/// actually needs: ordinary speech, names said the way they are always said,
/// warmth, and length.
///
/// Nothing here reaches a service. These are recordings, kept on this phone
/// like any other, and the screen says so — asking a living person to record
/// themselves is a different kind of ask from anything else in this app.
struct CaptureView: View {
    let personId: UUID

    @EnvironmentObject private var library: Library
    @StateObject private var recorder = VoiceRecorder()
    @ObservedObject private var localization = Localization.shared

    @State private var recordingId: String?
    @State private var problem: String?

    private var person: Person? { library.people.first { $0.id == personId } }

    /// Which prompts already have a recording against them, so an answered one
    /// is not asked for twice.
    private var answered: Set<String> {
        guard let person else { return [] }
        return Set(library.assets(for: person, source: .original).compactMap(\.promptId))
    }

    var body: some View {
        VStack(spacing: 0) {
            // No globe here. Switching language re-ids the whole tree, which
            // tears this screen down and cancels an in-progress recording — the
            // same way it once destroyed a clip on the player screen. A
            // five-minute story of someone still alive is not something to lose
            // to a mistap.
            AppBar(title: L("Recorded before it is needed"), trailing: AnyView(EmptyView()))

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    Group {
                        if let person {
                            Breadcrumb(name: person.name,
                                       relationship: person.relationship,
                                       photo: library.photoURL(for: person))
                        }
                        Headline(text: L("While they are\nstill here."))
                        SubText(text: L("Most families find they have nothing usable — a few seconds of someone laughing behind a video, and that is all. These are worth having whatever happens, and together they are what a voice needs."))
                    }

                    if let problem {
                        ErrorNote(message: problem)
                    }

                    if recorder.isRecording {
                        LiveMeter(meter: recorder.meter)
                    }

                    Text(L("Nothing here is sent anywhere. These are recordings, kept on this phone like any other."))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(Composer.capturePrompts, id: \.id) { prompt in
                        card(prompt)
                    }
                }
                .padding(.horizontal, Theme.Metric.screenPadding)
                .padding(.bottom, Theme.Space.xl)
            }
        }
        .background(Theme.Palette.paper)
        .onDisappear { if recorder.isRecording { recorder.cancel() } }
    }

    private func card(_ prompt: CapturePrompt) -> some View {
        let words = uiIsArabic ? prompt.arabic : prompt.english
        let isThisOne = recordingId == prompt.id
        return Panel {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                if answered.contains(prompt.id) {
                    HStack {
                        Spacer()
                        Text(L("Recorded"))
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Palette.forest)
                    }
                }
                BidiText(value: words, font: Theme.Font.body)
                Button(isThisOne ? L("Stop recording") : L("Record this")) {
                    Task { await toggle(prompt) }
                }
                .buttonStyle(QuietButtonStyle())
                // One at a time, always: two overlapping recordings would both
                // be wrong and neither would say so.
                .disabled(recorder.isRecording && !isThisOne)
            }
        }
    }

    /// @MainActor for the same reason as LettersView.open, and more urgently:
    /// recorder.start/stop mutate @Published on VoiceRecorder and its meter, and
    /// AVAudioSession.setActive is not safe to call off the main thread.
    @MainActor
    private func toggle(_ prompt: CapturePrompt) async {
        problem = nil

        if recordingId == prompt.id {
            recordingId = nil
            guard let result = recorder.stop() else { return }
            guard let person else {
                try? FileManager.default.removeItem(at: result.url)
                return
            }
            guard result.capturedSound else {
                problem = L("That recording came out silent. Nothing reached the microphone — check nothing is covering it and try again.")
                try? FileManager.default.removeItem(at: result.url)
                return
            }
            // Read BEFORE deleting, and say so when either step fails. This
            // used to collapse an unreadable file into empty Data and return
            // without a word, leaving a card that looked untouched and a take
            // that could not be made again.
            guard let data = try? Data(contentsOf: result.url), !data.isEmpty else {
                problem = L("That recording could not be read from this phone. Try importing it again.")
                try? FileManager.default.removeItem(at: result.url)
                return
            }
            let stored = library.storeAudio(data: data,
                                   for: person,
                                   source: .original,
                                   text: uiIsArabic ? prompt.arabic : prompt.english,
                                   duration: result.duration,
                                   modelId: nil,
                                   provenance: nil,
                                   intent: nil,
                                   content: nil,
                                   isSaved: true,
                                   promptId: prompt.id,
                                   fileExtension: "m4a")
            try? FileManager.default.removeItem(at: result.url)
            if stored == nil {
                problem = library.storageError
                    ?? L("The audio arrived but could not be saved to this phone.")
            }
            return
        }

        guard !recorder.isRecording else { return }
        guard await recorder.requestPermission() else {
            problem = recorder.permissionDenied
                ? L("Microphone access is off. Turn it on in Settings.")
                : L("Microphone access was not granted.")
            return
        }
        recorder.start(purpose: .voiceSample)
        if let failure = recorder.error {
            problem = failure
            return
        }
        recordingId = prompt.id
    }
}
