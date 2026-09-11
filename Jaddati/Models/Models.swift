import Foundation

/// How a voice should be performed. These map one-to-one onto the provider's
/// `voice_settings`, which is the only real fine-tuning available for an
/// instant clone — the clone itself is fixed once created.
///
///  - stability   low = more variable and emotional, high = flatter and safer
///  - similarity  how hard to push towards the original recording. Very high
///                also reproduces any noise in that recording.
///  - style       exaggerates the speaker's manner. Costs latency. 0 is safest.
struct VoiceTuning: Codable, Equatable, Hashable {
    var stability: Double = 0.45
    var similarity: Double = 0.80
    var style: Double = 0.0
    var speakerBoost: Bool = true
    /// 1.0 is the provider's default. Below 1 is slower. The default here is
    /// deliberately under 1: at full speed the output was hard to follow, and
    /// an elderly voice reading to someone should not be brisk.
    var speed: Double = 0.88

    /// The three presets are named for how the voice DELIVERS the words, never
    /// for how close it gets to the person. A preset called "Exactly them"
    /// would be a promise the technology cannot keep.
    ///
    /// `steady` and `warm` are kept as stored names so tunings already saved on
    /// a person still decode; the interface calls them Gentle and Storytelling.

    /// Balanced. What a first-time listener should hear.
    static let natural = VoiceTuning(stability: 0.45, similarity: 0.80, style: 0.0,
                                     speed: 0.88)
    /// Even and unhurried. The safest thing to put on a stage.
    static let steady = VoiceTuning(stability: 0.75, similarity: 0.80, style: 0.0,
                                    speed: 0.85)
    /// More shape to the reading, for a story. Occasionally an odd line.
    static let warm = VoiceTuning(stability: 0.30, similarity: 0.85, style: 0.30,
                                  speed: 0.92)

    static var gentle: VoiceTuning { .steady }
    static var storytelling: VoiceTuning { .warm }

    /// Decoded field by field, tolerating anything missing.
    ///
    /// This is not defensiveness for its own sake. `speed` was added to this
    /// struct after people already had libraries on disk, and Swift's
    /// synthesised Codable does NOT fall back to a property's default value for
    /// a key that is absent — it throws. That throw propagates VoiceTuning →
    /// Person → [Person] → the whole index, which the loader then quarantines
    /// as corrupt, and every person, clip and book disappears from the app while
    /// the audio files sit untouched on disk with nothing pointing at them.
    ///
    /// Any future field added here must be read the same way.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stability    = try c.decodeIfPresent(Double.self, forKey: .stability) ?? 0.45
        similarity   = try c.decodeIfPresent(Double.self, forKey: .similarity) ?? 0.80
        style        = try c.decodeIfPresent(Double.self, forKey: .style) ?? 0.0
        speakerBoost = try c.decodeIfPresent(Bool.self, forKey: .speakerBoost) ?? true
        speed        = try c.decodeIfPresent(Double.self, forKey: .speed) ?? 0.88
    }

    init(stability: Double = 0.45, similarity: Double = 0.80, style: Double = 0.0,
         speakerBoost: Bool = true, speed: Double = 0.88) {
        self.stability = stability
        self.similarity = similarity
        self.style = style
        self.speakerBoost = speakerBoost
        self.speed = speed
    }

    var presetName: String? {
        switch self {
        case Self.natural: return L("Natural")
        case Self.steady:  return L("Gentle")
        case Self.warm:    return L("Storytelling")
        default:           return nil
        }
    }
}

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

    /// Filename only, resolved against the library's photo directory at read
    /// time — the iOS container path changes on every install.
    var photoFilename: String? = nil

    /// How this person's voice is performed. Optional so an index written
    /// before this existed still decodes.
    var tuning: VoiceTuning? = nil

    var voiceTuning: VoiceTuning { tuning ?? .natural }

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

    /// Which experience produced this clip, as `Intent.rawValue`. Lets each
    /// screen show what it made, instead of everything landing in one pile.
    var intentRaw: String? = nil

    var intent: Intent? { intentRaw.flatMap(Intent.init(rawValue:)) }

    /// Set only for generated book pages, so an already-read page can be found
    /// and replayed instead of paid for twice.
    /// `ContentProvenance.rawValue`. Optional because Swift's synthesised
    /// Codable does not fall back to a property default for a key that is
    /// absent, so every library written before this field existed must still
    /// decode.
    var contentKind: String? = nil

    var contentProvenance: ContentProvenance? {
        contentKind.flatMap(ContentProvenance.init(rawValue:))
            ?? intent?.defaultContentProvenance
    }

    var bookId: UUID? = nil
    var pageIndex: Int? = nil

    var isGenerated: Bool { source == .generated }
}

/// A text the user brought in and wants read aloud, already split into pages.
/// The pages live here rather than in the original file so a book keeps working
/// after the imported file is gone, and so a page can be looked up by index.
struct Book: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var personId: UUID
    var title: String
    var pages: [String]
    /// Where the reader left off.
    var currentPage: Int = 0
    var addedAt: Date = Date()

    var pageCount: Int { pages.count }
    var totalCharacters: Int { pages.reduce(0) { $0 + $1.count } }

    func page(_ index: Int) -> String? {
        pages.indices.contains(index) ? pages[index] : nil
    }
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

    /// nil or "memory" for a family memory; "affirmation" for a comfort line
    /// the user added to the bank. Optional so older stored notes still decode.
    var kind: String? = nil

    static let affirmationKind = "affirmation"
    var isAffirmation: Bool { kind == Self.affirmationKind }
}

/// What kind of thing the user asked for. Drives the copy on the player and
/// the label stored with the result.
/// What the WORDS are, as distinct from whose voice says them. Stored on the
/// asset rather than derived from whichever screen is showing it, so an
/// invented story is still marked invented three weeks later in the archive.
///
/// The raw values are persisted. Never rename one.
enum ContentProvenance: String, Codable, CaseIterable {
    case wordsSuppliedByYou
    case comfortLine
    case inventedStory
    case keptWords
    case importedText
    case answerWhileReading

    var label: String {
        switch self {
        case .wordsSuppliedByYou: return L("Words supplied by you")
        case .comfortLine:        return L("Comfort line")
        case .inventedStory:      return L("Invented story")
        case .keptWords:          return L("Saved words")
        case .importedText:       return L("From an imported file")
        case .answerWhileReading: return L("Answer to a question")
        }
    }

    var icon: String {
        switch self {
        case .wordsSuppliedByYou: return "pencil"
        case .comfortLine:        return "leaf"
        case .inventedStory:      return "sparkles"
        case .keptWords:          return "tray.full"
        case .importedText:       return "doc.text"
        case .answerWhileReading: return "questionmark.bubble"
        }
    }

    /// Fiction is the one that must never be quietly dropped.
    var mustAlwaysShow: Bool { self == .inventedStory }
}

enum Intent: String, Codable, CaseIterable {
    case saySomething
    case comfort
    case storyFiction
    case storyFromMemories
    case readBook

    /// Display names only. `rawValue` is what every stored clip points at, so
    /// renaming a case would orphan audio the user has already kept.
    ///
    /// "Comfort me" and "A memory, retold" both addressed the dead person as if
    /// they were doing something. They are now named for what they actually
    /// are: a line the user picked, and a collection the user wrote.
    var title: String {
        switch self {
        case .saySomething:      return L("Say something")
        case .comfort:           return L("Words of comfort")
        case .storyFiction:      return L("Tell me a story")
        case .storyFromMemories: return L("Words & memories")
        case .readBook:          return L("Read me a book")
        }
    }

    /// One credit is roughly one character, so this is also a spending limit.
    /// Stories get more room because they are the one thing meant to run long.
    var characterLimit: Int {
        switch self {
        case .saySomething:      return 800
        case .comfort:           return 400
        case .storyFiction:      return 2_500
        case .storyFromMemories: return 800
        case .readBook:          return 1_500
        }
    }

    var subtitle: String {
        switch self {
        case .saySomething:      return L("Words you choose, in a recreated voice")
        case .comfort:           return L("A short, steadying line you choose")
        case .storyFiction:      return L("An invented story for a quiet moment")
        case .storyFromMemories: return L("The words you have kept, in one place")
        case .readBook:          return L("Your own text, a page at a time")
        }
    }

    /// The content label a clip from this experience is born with.
    var defaultContentProvenance: ContentProvenance {
        switch self {
        case .saySomething:      return .wordsSuppliedByYou
        case .comfort:           return .comfortLine
        case .storyFiction:      return .inventedStory
        case .storyFromMemories: return .keptWords
        case .readBook:          return .importedText
        }
    }

    var icon: String {
        switch self {
        case .saySomething:      return "text.quote"
        case .comfort:           return "heart"
        case .storyFiction:      return "moon.stars"
        case .storyFromMemories: return "book.closed"
        case .readBook:          return "books.vertical"
        }
    }

    /// Fiction must announce itself. A retelling grounded in family notes must
    /// say where it came from. Neither may be presented as a real memory.
    var provenanceNote: String? {
        switch self {
        case .storyFiction:
            return "An invented story. Not a real memory."
        case .readBook:
            return "Read from a file you provided."
        default:
            // Everything else is words a person typed. Nothing to disclaim.
            return nil
        }
    }
}
