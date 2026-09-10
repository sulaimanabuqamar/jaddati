import Foundation
import AVFoundation

/// What a finished recording turned out to be.
///
/// `capturedSound` exists because of a real failure in the first version of
/// this project: a recording library returned success and wrote a valid, empty
/// 28-byte m4a every single time. A recorder that reports success is not the
/// same as a recorder that captured audio, and the difference is only visible
/// if something checks. Cloning silence costs credits and fails on stage.
struct RecordingResult {
    let url: URL
    let duration: Double
    let bytes: Int
    let peakDecibels: Float

    /// Digital silence sits near -160 dB. Real speech, even quiet and distant,
    /// peaks well above -40.
    var capturedSound: Bool { bytes > 8_000 && peakDecibels > -40 }
}

final class VoiceRecorder: ObservableObject {

    /// A sample to be cloned wants fidelity. A sentence on its way to a
    /// transcriber wants to be small — Whisper resamples to 16 kHz anyway, so
    /// anything more is upload time for nothing.
    enum Purpose {
        case voiceSample
        case dictation

        var settings: [String: Any] {
            switch self {
            case .voiceSample:
                return [AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                        AVSampleRateKey: 44_100.0,
                        AVNumberOfChannelsKey: 1,
                        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue]
            case .dictation:
                return [AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                        AVSampleRateKey: 16_000.0,
                        AVNumberOfChannelsKey: 1,
                        AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue]
            }
        }

        var maximumDuration: Double {
            switch self {
            case .voiceSample: return 300      // five minutes
            case .dictation: return 60
            }
        }
    }

    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: Double = 0
    /// 0 to 1, for a level meter. Someone watching a still bar knows to stop
    /// and check before they spend credits on the result.
    @Published private(set) var level: Double = 0
    @Published var error: String?
    /// Set when the cap is reached so the screen can stop and keep what it has.
    @Published private(set) var reachedLimit = false

    private var recorder: AVAudioRecorder?
    private var ticker: Timer?
    private var peak: Float = -160
    private var purpose: Purpose = .voiceSample

    var hasPermission: Bool {
        AVAudioApplication.shared.recordPermission == .granted
    }

    var permissionDenied: Bool {
        AVAudioApplication.shared.recordPermission == .denied
    }

    func requestPermission() async -> Bool {
        if hasPermission { return true }
        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func start(purpose: Purpose) {
        guard !isRecording else { return }
        self.purpose = purpose
        error = nil
        peak = -160
        elapsed = 0
        level = 0
        reachedLimit = false

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("recording-\(UUID().uuidString).m4a")

        do {
            let session = AVAudioSession.sharedInstance()
            // .playAndRecord rather than .record: the reader pauses a story to
            // take a question and has to speak again straight afterwards, and
            // .record leaves playback dead until the session is torn down.
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)

            let newRecorder = try AVAudioRecorder(url: url, settings: purpose.settings)
            newRecorder.isMeteringEnabled = true
            guard newRecorder.prepareToRecord(), newRecorder.record() else {
                error = "The microphone could not be started."
                return
            }
            recorder = newRecorder
            isRecording = true
            startTicking()
        } catch {
            self.error = "The microphone could not be started. \(error.localizedDescription)"
        }
    }

    /// Stops and returns what was actually captured. Nil means nothing usable.
    @discardableResult
    func stop() -> RecordingResult? {
        guard let recorder else { return nil }
        let duration = recorder.currentTime
        recorder.stop()
        stopTicking()
        isRecording = false
        self.recorder = nil
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        let url = recorder.url
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let bytes = (attributes?[.size] as? Int) ?? 0
        return RecordingResult(url: url, duration: duration, bytes: bytes, peakDecibels: peak)
    }

    func cancel() {
        guard let recorder else { return }
        let url = recorder.url
        recorder.stop()
        stopTicking()
        isRecording = false
        self.recorder = nil
        level = 0
        elapsed = 0
        try? FileManager.default.removeItem(at: url)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: Metering

    private func startTicking() {
        ticker?.invalidate()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)   // keeps running while scrolling
        ticker = timer
    }

    private func tick() {
        guard let recorder, recorder.isRecording else { return }
        recorder.updateMeters()
        let power = recorder.peakPower(forChannel: 0)
        peak = max(peak, power)
        // -60 dB floor, mapped to 0...1 for a bar that moves at speaking volume.
        level = Double(max(0, min(1, (power + 60) / 60)))
        elapsed = recorder.currentTime

        // Nothing is lost when this trips — stop() hands back everything
        // recorded up to that point.
        if elapsed >= purpose.maximumDuration { reachedLimit = true }
    }

    private func stopTicking() {
        ticker?.invalidate()
        ticker = nil
    }
}
