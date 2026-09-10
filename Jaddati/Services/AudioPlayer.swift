import Foundation
import AVFoundation
import Combine

/// One player for the whole app, so two things can never speak at once.
///
/// Progress comes from `AVAudioPlayer.currentTime` on a timer. It is the real
/// playback position — nothing here is animated independently of the audio.
final class AudioPlayer: NSObject, ObservableObject {

    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var playingAssetId: UUID?
    @Published var playbackError: String?

    /// Applies to playback only, so a clip already generated can be slowed
    /// without paying to make it again. AVAudioPlayer time-stretches, so the
    /// pitch does not drop.
    @Published var playbackRate: Float = 1.0 {
        didSet { player?.rate = playbackRate }
    }

    private var player: AVAudioPlayer?
    private var ticker: Timer?

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    deinit {
        ticker?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    func isPlaying(assetId: UUID) -> Bool {
        isPlaying && playingAssetId == assetId
    }

    /// Starts `url` if it is not already the playing asset. Never pauses.
    /// The listening screen uses this on appear; using the toggle there meant
    /// opening a clip that was already playing silenced it.
    func ensurePlaying(url: URL, assetId: UUID) {
        if playingAssetId == assetId, let existing = player, existing.isPlaying { return }
        if playingAssetId == assetId, player != nil { resume(); return }
        play(url: url, assetId: assetId)
    }

    /// Starts `url`. Calling it for the asset already playing toggles pause.
    func play(url: URL, assetId: UUID) {
        if playingAssetId == assetId, let existing = player {
            existing.isPlaying ? pause() : resume()
            return
        }

        stop()

        guard FileManager.default.fileExists(atPath: url.path) else {
            playbackError = "That audio file is missing from this phone."
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)

            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.delegate = self
            newPlayer.enableRate = true          // must precede prepareToPlay()
            newPlayer.rate = playbackRate
            newPlayer.prepareToPlay()
            player = newPlayer
            duration = newPlayer.duration
            currentTime = 0
            playingAssetId = assetId
            playbackError = nil
            newPlayer.play()
            isPlaying = true
            startTicking()
        } catch {
            playbackError = "This audio could not be played. It may be an unsupported format."
            playingAssetId = nil
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopTicking()
    }

    func resume() {
        guard let player else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        // At end-of-file, play() from the current position is unreliable.
        if player.currentTime >= player.duration - 0.05 {
            player.currentTime = 0
            currentTime = 0
        }
        player.play()
        isPlaying = true
        startTicking()
    }

    func seek(toProgress fraction: Double) {
        guard let player, duration > 0 else { return }
        let target = min(max(fraction, 0), 1) * duration
        player.currentTime = target
        currentTime = target
    }

    func stop() {
        stopTicking()
        player?.stop()
        player = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        playingAssetId = nil
        // Release the session so other audio on the phone is not left suppressed.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: Ticking

    private func startTicking() {
        stopTicking()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, let player = self.player else { return }
            self.currentTime = player.currentTime
        }
        RunLoop.main.add(timer, forMode: .common)   // keeps ticking while scrolling
        ticker = timer
    }

    private func stopTicking() {
        ticker?.invalidate()
        ticker = nil
    }

    // MARK: Interruptions (a phone call mid-playback must not leave a stuck UI)

    @objc private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch type {
            case .began:
                self.pause()
            default:
                // Deliberately no auto-resume. After an interruption the user
                // decides whether to hear it again.
                self.isPlaying = false
                self.stopTicking()
            }
        }
    }
}

extension AudioPlayer: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isPlaying = false
            self.currentTime = self.duration
            self.stopTicking()
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            self?.playbackError = "Playback stopped unexpectedly."
            self?.isPlaying = false
        }
    }
}
