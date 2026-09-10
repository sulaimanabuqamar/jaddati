import Foundation

/// A person whose voice has been preserved. One profile per loved one.
struct Person: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var name: String                  // as the family says it, e.g. "Jaddati"
    var fullName: String = ""         // optional formal name
    var relationship: String = ""     // "Grandmother", "جدتي"
    var createdAt: Date = Date()

    /// The ElevenLabs voice identifier once a clone exists.
    /// nil means: samples may exist, but nothing can be generated yet.
    var voiceId: String? = nil
    var voiceCreatedAt: Date? = nil

    /// The provider can hand back a voice id that is not yet usable. Until this
    /// is false, the voice exists but cannot speak, and the UI must not claim
    /// it is ready.
    var voiceRequiresVerification: Bool? = nil

    /// Recorded at the moment of upload. We keep it because the whole product
    /// rests on it — see AddVoiceView.
    var consentConfirmedAt: Date? = nil

    /// Ready to speak. Deliberately stricter than "a voice id exists": a voice
    /// can exist and still be unusable, and claiming otherwise produces a
    /// profile that says "Voice ready" while every generation fails.
    var hasVoice: Bool {
        voiceId != nil && voiceRequiresVerification != true && !voiceIsUnavailableHere
    }

    /// A voice was created but the provider will not let it speak yet.
    var voicePendingVerification: Bool { voiceId != nil && voiceRequiresVerification == true }

    /// Minted by the offline test mode. No such voice exists at the provider.
    var voiceIsPlaceholder: Bool {
        voiceId?.hasPrefix(AppConfig.placeholderVoicePrefix) == true
    }

    /// The stored voice cannot be used against the service the app is currently
    /// pointed at — i.e. a test-mode voice while test mode is off. This is the
    /// state that silently produced "invalid ID" on every generation.
    var voiceIsUnavailableHere: Bool {
        voiceIsPlaceholder && !AppConfig.isUsingMock
    }
}

/// Where a piece of audio came from. This distinction is load-bearing:
/// the app must never blur an original recording into a generated one.
enum AudioSource: String, Codable {
    case original      // a real recording of the person
    case generated     // synthesised in the recreated voice
}

/// Any playable audio the app owns.
struct AudioAsset: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var personId: UUID
    var source: AudioSource

    /// Filename ONLY, never an absolute path.
    /// iOS gives the app container a fresh UUID on every install, so an absolute
    /// path saved today is dangling tomorrow. Resolved against the audio
    /// directory at read time by `Library.url(for:)`.
    var filename: String

    /// For generated audio: the words that were spoken.
    /// For originals: an optional note from the family.
    var text: String = ""

    var createdAt: Date = Date()
    var durationSeconds: Double = 0

    /// Which model produced it. Only meaningful for `.generated`.
    var modelId: String? = nil

    /// Marks the generated pieces the user chose to keep. Generated audio starts
    /// unkept and is removed if the listener leaves without saving.
    var isSaved: Bool = true

    /// Where the words came from, stored WITH the audio rather than derived from
    /// whichever screen happens to be showing it. A fiction label that survives
    /// only until you reopen the clip from the archive is not a label.
    var provenance: String? = nil

    var isGenerated: Bool { source == .generated }
}

/// A memory the family supplies in their own words. Used to ground a retelling.
/// Kept separate from anything the model invents — a story built from these is
/// labelled as a family account, a story without them is labelled fiction.
struct FamilyNote: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var personId: UUID
    var text: String
    var addedBy: String = ""
    var createdAt: Date = Date()
}

/// What kind of thing the user asked for. Drives the copy on the player and
/// the label stored with the result.
enum Intent: String, Codable, CaseIterable {
    case saySomething
    case comfort
    case storyFiction
    case storyFromMemories

    var title: String {
        switch self {
        case .saySomething:      return "Say something"
        case .comfort:           return "Comfort me"
        case .storyFiction:      return "Tell me a story"
        case .storyFromMemories: return "A memory, retold"
        }
    }

    var subtitle: String {
        switch self {
        case .saySomething:      return "Words you choose, in their voice"
        case .comfort:           return "Something steadying to hear"
        case .storyFiction:      return "An invented bedtime story"
        case .storyFromMemories: return "Built only from what your family wrote down"
        }
    }

    var icon: String {
        switch self {
        case .saySomething:      return "text.quote"
        case .comfort:           return "heart"
        case .storyFiction:      return "moon.stars"
        case .storyFromMemories: return "book.closed"
        }
    }

    /// Fiction must announce itself. A retelling grounded in family notes must
    /// say where it came from. Neither may be presented as a real memory.
    var provenanceNote: String? {
        switch self {
        case .storyFiction:
            return "An invented story. Not a real memory."
        case .storyFromMemories:
            return "Retold from memories your family wrote down."
        default:
            return nil
        }
    }
}
