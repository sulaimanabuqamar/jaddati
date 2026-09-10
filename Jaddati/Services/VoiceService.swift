import Foundation

/// What the app needs from a voice provider. Views depend on this, never on
/// ElevenLabs directly, so the direct client can be swapped for a server proxy
/// without touching a single screen.
protocol VoiceService {
    /// Uploads a sample and returns the new voice identifier.
    func createVoice(name: String, sampleURL: URL) async throws -> String
    /// Speaks `text` in `voiceId` and returns MP3 data.
    func synthesize(text: String, voiceId: String, modelId: String) async throws -> Data
}

/// Failures the user might actually see, each with wording that says what to do.
enum VoiceServiceError: LocalizedError {
    case notConfigured
    case textTooLong(limit: Int)
    case sampleTooShort
    case unauthorised
    case outOfCredits
    case rateLimited
    case offline
    case timedOut
    case provider(status: Int, detail: String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Voices aren't set up on this build yet."
        case .textTooLong(let limit):
            return "That's a bit long — keep it under \(limit) characters."
        case .sampleTooShort:
            return "That recording is too short to build a voice from. About a minute works best."
        case .unauthorised:
            return "The voice service rejected the key on this build."
        case .outOfCredits:
            return "This month's voice credits are used up. Saved memories still play."
        case .rateLimited:
            return "The voice service is busy. Wait a moment and try again."
        case .offline:
            return "No connection. New audio needs the internet — saved memories still play."
        case .timedOut:
            return "The voice service took too long. Your words are still here — try again."
        case .provider(let status, let detail):
            return "The voice service returned an error (\(status)). \(detail)"
        case .badResponse:
            return "The voice service sent something unexpected."
        }
    }
}
