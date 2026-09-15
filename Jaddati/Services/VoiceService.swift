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
    /// Remove the cloned voice from the provider.
    ///
    /// This exists because the app has to be able to answer "how do I get this
    /// deleted?" with something a person can actually do. The voice is held
    /// under the developer's provider account, not the user's — so without
    /// this call the honest answer was "you cannot", and a family who changed
    /// their mind had no way to act on it. A voice that is already gone counts
    /// as success: the point is that it is not there any more.
    func deleteVoice(voiceId: String) async throws

    /// Hand ONE voice slot back at the provider, without asking anybody.
    ///
    /// The provider account has a fixed number of custom-voice slots, and
    /// until now nothing ever gave one back: every trial run left a voice
    /// behind, and eventually the app told the person standing in front of it
    /// to go and tidy up a dashboard they have never seen. That is the same as
    /// the app not working. The relay does this for the web build; a phone on
    /// its own key had no equivalent.
    ///
    /// `keeping` is every voice this phone still needs, and is never touched.
    /// Returns false when there was nothing safe to remove — the caller then
    /// reports the refusal rather than deleting something that matters.
    func freeOneVoiceSlot(keeping: Set<String>) async throws -> Bool
}

extension VoiceService {
    /// Most providers cannot do this, and the offline test mode has no slots
    /// to give back. Saying so is the honest default.
    func freeOneVoiceSlot(keeping: Set<String>) async throws -> Bool { false }

    /// Create a voice, making room first if the account is full.
    ///
    /// Two screens need this — the one where a family adds a voice, and the
    /// one where a voice that was handed on has to be rebuilt before the next
    /// sentence can be said — and neither of them should have to know that
    /// slots exist. One retry, never a loop.
    func createVoiceMakingRoom(name: String, sampleURL: URL,
                               keeping: Set<String>) async throws -> CreatedVoice {
        do {
            return try await createVoice(name: name, sampleURL: sampleURL)
        } catch VoiceServiceError.voiceLimitReached {
            guard try await freeOneVoiceSlot(keeping: keeping) else {
                throw VoiceServiceError.voiceLimitReached
            }
            return try await createVoice(name: name, sampleURL: sampleURL)
        }
    }
}

/// Failures the user might actually see, each with wording that says what to do.
enum VoiceServiceError: LocalizedError, Equatable {
    case notConfigured
    case textTooLong(limit: Int)
    /// The words were refused before anything was spent. Deliberately does
    /// not name the word back at the person.
    case refused
    case sampleUnreadable
    case sampleRejected(String)
    case voiceUnavailable(String)
    case unauthorised
    case outOfCredits
    case voiceLimitReached
    /// The signed-in account already holds a recreated voice. Different from
    /// the account being full, and the remedy is different too, so it is its
    /// own case. Named for the phone because that is what it used to mean: the
    /// relay keyed the lock to a device before it keyed it to a person.
    case deviceAlreadyHasVoice
    /// Nobody is signed in, and the relay bills somebody for this. Carries its
    /// own sentence because the three calls that need it are asking for
    /// different things, and "to make new audio" is not true of a deletion.
    case signInRequired(String)
    case rateLimited
    case offline
    case timedOut
    case provider(status: Int, detail: String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return L("The voice service is not set up on this build.")
        case .textTooLong(let limit):
            return L("Shorten the text to fit the limit.") + " (\(limit))"
        case .refused:
            return L("That will not be spoken in their voice.")
        case .sampleUnreadable:
            return L("That recording could not be read from this phone. Try importing it again.")
        case .sampleRejected(let why):
            let head = L("The voice service would not accept that recording.")
            return why.isEmpty
                ? head + " " + L("Try a longer, clearer one.")
                : head + " " + why
        case .voiceUnavailable(let detail):
            let head = L("That voice is not available at the voice service.")
            return (detail.isEmpty ? head : head + " (\(detail))")
                + " " + L("Add their voice again to create a new one.")
        case .unauthorised:
            return L("The voice service rejected the key on this build.")
        case .outOfCredits:
            return L("This month's voice credits are used up. Saved memories still play.")
        case .voiceLimitReached:
            return L("This account has no free voice slots left. Remove an unused voice at the voice service, then try again.")
        case .deviceAlreadyHasVoice:
            return L("You already have a recreated voice. Remove that person, or the voice on their Setup screen, before making another.")
        case .signInRequired(let why):
            return why
        case .rateLimited:
            return L("The voice service is busy. Wait a moment and try again.")
        case .offline:
            return L("No connection. New audio needs the internet — saved memories still play.")
        case .timedOut:
            return L("The voice service took too long. Your words are still here — try again.")
        case .provider(let status, let detail):
            return L("The voice service returned an error.") + " (\(status)) " + detail
        case .badResponse:
            return L("The voice service sent something unexpected.")
        }
    }
}
