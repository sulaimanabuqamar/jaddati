import Foundation

/// The result of creating a voice.
///
/// `requiresVerification` matters more than it looks: ElevenLabs can return a
/// voice id that cannot yet speak. Treating that as success is how you end up
/// on stage with a screen saying "Voice ready" and nothing coming out.
struct CreatedVoice: Equatable {
    let id: String
    let requiresVerification: Bool
}

/// What the app needs from a voice provider. Views depend on this, never on
/// ElevenLabs directly, so the direct client can be swapped for a server proxy
/// without touching a single screen.
protocol VoiceService {
    func createVoice(name: String, sampleURL: URL) async throws -> CreatedVoice
    func synthesize(text: String, voiceId: String, modelId: String,
                    tuning: VoiceTuning) async throws -> Data
}

/// Failures the user might actually see, each with wording that says what to do.
enum VoiceServiceError: LocalizedError, Equatable {
    case notConfigured
    case textTooLong(limit: Int)
    case sampleUnreadable
    case sampleRejected(String)
    case voiceUnavailable(String)
    case unauthorised
    case outOfCredits
    case voiceLimitReached
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
        case .sampleUnreadable:
            return "That recording could not be read from this phone. Try importing it again."
        case .sampleRejected(let why):
            return why.isEmpty
                ? "The voice service would not accept that recording. Try a longer, cleaner one."
                : "The voice service would not accept that recording. \(why)"
        case .voiceUnavailable(let detail):
            return "That voice is not available at the voice service\(detail.isEmpty ? "" : " (\(detail))"). Add their voice again to create a new one."
        case .unauthorised:
            return "The voice service rejected the key on this build."
        case .outOfCredits:
            return "This month's voice credits are used up. Saved memories still play."
        case .voiceLimitReached:
            return "This account has no free voice slots left. Delete an unused voice in the ElevenLabs account, then try again."
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
