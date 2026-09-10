#if DEBUG
import Foundation
import AVFoundation

/// Offline stand-in for the real provider, so the whole app — navigation,
/// storage, playback, progress, error states, relaunch — can be exercised on
/// the phone with no API key, no voice sample, and no credits spent.
///
/// Two deliberate properties:
///
///  1. It is inside `#if DEBUG`, so it does not exist in a Release build. It
///     cannot reach the demo even by accident.
///  2. What it returns is an obvious soft tone, not speech. Nobody can mistake
///     it for a working voice, which is the point — a mock that sounds real is
///     how you end up demoing a cached file and calling it live generation.
struct MockVoiceService: VoiceService {

    func createVoice(name: String, sampleURL: URL) async throws -> CreatedVoice {
        try? await Task.sleep(nanoseconds: 1_200_000_000)     // feel the wait
        return CreatedVoice(id: "\(AppConfig.placeholderVoicePrefix)\(UUID().uuidString.prefix(8))",
                            requiresVerification: false)
    }

    func synthesize(text: String, voiceId: String, modelId: String) async throws -> Data {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw VoiceServiceError.badResponse }
        guard trimmed.count <= AppConfig.maxCharactersPerGeneration else {
            throw VoiceServiceError.textTooLong(limit: AppConfig.maxCharactersPerGeneration)
        }

        // Roughly the pace of speech, so the progress bar and timings behave
        // like the real thing.
        let seconds = max(1.5, min(30.0, Double(trimmed.count) / 14.0))
        try? await Task.sleep(nanoseconds: 900_000_000)

        // Type "fail" anywhere in the text to exercise the error path on device.
        if trimmed.lowercased().contains("fail") { throw VoiceServiceError.rateLimited }

        return Self.tone(seconds: seconds)
    }

    /// A minimal 16-bit mono PCM WAV, built by hand so nothing has to ship in
    /// the bundle. Gently pulsed and faded so it is pleasant to sit through.
    static func tone(seconds: Double, sampleRate: Double = 22_050) -> Data {
        let frameCount = Int(seconds * sampleRate)
        var samples = Data(capacity: frameCount * 2)

        for i in 0..<frameCount {
            let t = Double(i) / sampleRate
            let carrier = sin(2.0 * Double.pi * 196.0 * t)
            let pulse = 0.5 + 0.5 * sin(2.0 * Double.pi * 1.6 * t)
            let fade = min(1.0, min(t / 0.08, (seconds - t) / 0.20))
            let value = carrier * pulse * fade * 0.18
            let scaled = Int16(max(-1.0, min(1.0, value)) * 32_767)
            withUnsafeBytes(of: scaled.littleEndian) { samples.append(contentsOf: $0) }
        }

        var out = Data()
        func ascii(_ s: String) { out.append(contentsOf: Array(s.utf8)) }
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { out.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { out.append(contentsOf: $0) } }

        ascii("RIFF"); u32(UInt32(36 + samples.count)); ascii("WAVE")
        ascii("fmt "); u32(16); u16(1); u16(1)
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate) * 2); u16(2); u16(16)
        ascii("data"); u32(UInt32(samples.count))
        out.append(samples)
        return out
    }
}
#endif
