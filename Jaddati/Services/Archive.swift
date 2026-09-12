import Foundation

/// One voice, the whole family.
///
/// A grandmother belongs to more than one phone. This moves her to another one,
/// and the reason it works at all is that the voice lives at the voice service
/// rather than on the device — so a second phone holding the same identifier
/// speaks in her immediately, without paying to clone her twice and without
/// taking a second voice slot for the same person.
///
/// What travels: the person, the family's notes, anything still sealed, the
/// original recordings, and that identifier. What does not: clips already
/// generated. They are cheap to remake and expensive to carry, and a file too
/// large to send is a file that never gets sent.
enum Archive {

    static let version = 1

    /// Above this the recordings are left behind rather than making a file too
    /// large to share. Sized to clear a WhatsApp document send with room over.
    static let maxBytes = 60 * 1024 * 1024

    // MARK: The file

    struct Payload: Codable {
        var jaddati: Int
        var exportedAt: Date
        var person: PersonCard
        // Optional so a file written by an older or newer build — or one that
        // simply had none of something — still opens. A whole archive refused
        // because it carries no letters is a family told their grandmother
        // could not be read.
        var notes: [NoteCard]?
        var letters: [LetterCard]?
        var recordings: [RecordingCard]?
    }

    /// Deliberately NOT the app's own types. Local ids must not travel — two
    /// phones sharing one id is a bug that only surfaces later, once both have
    /// edited the same person — and a wire format that drifts with the app's
    /// internals is a file that stops opening after a refactor.
    struct PersonCard: Codable {
        var name: String
        var fullName: String
        var relationship: String
        var voiceId: String?
        var voiceCreatedAt: Date?
        var voiceRequiresVerification: Bool?
        var consentConfirmedAt: Date?
        var tuning: VoiceTuning?
    }

    struct NoteCard: Codable {
        var text: String
        var addedBy: String
        var createdAt: Date
        var kind: String?
    }

    struct LetterCard: Codable {
        var text: String
        var occasion: String
        var deliverAt: Date
        var createdAt: Date
    }

    struct RecordingCard: Codable {
        var text: String
        var durationSeconds: Double
        var promptId: String?
        var fileExtension: String
        /// Base64. Large, but a family archive that needs a second file
        /// alongside it is one that arrives incomplete.
        var data: String
    }

    struct ExportResult {
        let url: URL
        let carried: Int
        let leftBehind: Int
    }

    enum Failure: LocalizedError {
        case notAnArchive
        case tooNew
        case empty

        var errorDescription: String? {
            switch self {
            case .notAnArchive: return L("That file is not a Jaddati archive.")
            case .tooNew:       return L("That archive was made by a newer version of Jaddati. Update this one first.")
            case .empty:        return L("That archive has no one in it.")
            }
        }
    }

    // MARK: Out

    /// Writes the archive to a temporary file and hands back its URL, ready for
    /// the share sheet. The result says how many recordings actually fitted: a
    /// silent partial export would leave a family believing the recordings are
    /// safe on the other phone when they are not.
    static func export(person: Person, library: Library) throws -> ExportResult {
        var recordings: [RecordingCard] = []
        var carried = 0, leftBehind = 0

        for asset in library.assets(for: person, source: .original) {
            let url = library.url(for: asset)
            guard let data = try? Data(contentsOf: url) else { leftBehind += 1; continue }
            guard carried + data.count <= maxBytes else { leftBehind += 1; continue }
            carried += data.count
            recordings.append(RecordingCard(
                text: asset.text,
                durationSeconds: asset.durationSeconds,
                promptId: asset.promptId,
                fileExtension: (asset.filename as NSString).pathExtension,
                data: data.base64EncodedString()))
        }

        let payload = Payload(
            jaddati: version,
            exportedAt: Date(),
            person: PersonCard(name: person.name,
                               fullName: person.fullName,
                               relationship: person.relationship,
                               voiceId: person.voiceId,
                               voiceCreatedAt: person.voiceCreatedAt,
                               voiceRequiresVerification: person.voiceRequiresVerification,
                               consentConfirmedAt: person.consentConfirmedAt,
                               tuning: person.tuning),
            notes: library.memories(for: person).map {
                NoteCard(text: $0.text, addedBy: $0.addedBy, createdAt: $0.createdAt, kind: $0.kind)
            },
            // Only unopened letters: an opened one is already a clip, and its
            // day has been and gone.
            letters: library.letters(for: person).filter { !$0.isOpened }.map {
                LetterCard(text: $0.text, occasion: $0.occasion,
                           deliverAt: $0.deliverAt, createdAt: $0.createdAt)
            },
            recordings: recordings)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        let safeName = person.name.isEmpty ? "jaddati" : person.name
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeName).jaddati.json")
        try data.write(to: file, options: .atomic)

        return ExportResult(url: file, carried: recordings.count, leftBehind: leftBehind)
    }

    // MARK: In

    struct ImportResult {
        let person: Person
        let notes: Int
        let letters: Int
        let restored: Int
    }

    /// The other side. She arrives with fresh local ids but keeps the voice
    /// identifier, which is the part that makes her speak here.
    @discardableResult
    static func importArchive(from url: URL, into library: Library) throws -> ImportResult {
        // A file handed over by the system files app is security-scoped, and
        // reading it without asking first fails with a permissions error that
        // looks exactly like a corrupt archive.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let payload = try? decoder.decode(Payload.self, from: data) else {
            throw Failure.notAnArchive
        }
        guard payload.jaddati <= version else { throw Failure.tooNew }
        guard !payload.person.name.isEmpty else { throw Failure.empty }

        let card = payload.person
        var person = Person(name: card.name)
        person.fullName = card.fullName
        person.relationship = card.relationship
        person.voiceId = card.voiceId
        person.voiceCreatedAt = card.voiceCreatedAt
        person.voiceRequiresVerification = card.voiceRequiresVerification
        person.consentConfirmedAt = card.consentConfirmedAt
        person.tuning = card.tuning
        person.voiceIsShared = true
        library.add(person)

        for note in payload.notes ?? [] {
            var arrived = FamilyNote(personId: person.id, text: note.text)
            arrived.addedBy = note.addedBy
            arrived.createdAt = note.createdAt
            arrived.kind = note.kind
            library.add(arrived)
        }
        for letter in payload.letters ?? [] {
            library.addLetter(for: person, text: letter.text,
                              occasion: letter.occasion, deliverAt: letter.deliverAt)
        }

        var restored = 0
        for recording in payload.recordings ?? [] {
            guard let bytes = Data(base64Encoded: recording.data) else { continue }
            // One unreadable recording must not cost the family the other nine.
            if library.storeAudio(data: bytes,
                                  for: person,
                                  source: .original,
                                  text: recording.text,
                                  duration: recording.durationSeconds,
                                  isSaved: true,
                                  promptId: recording.promptId,
                                  fileExtension: recording.fileExtension.isEmpty
                                      ? "m4a" : recording.fileExtension) != nil {
                restored += 1
            }
        }

        return ImportResult(person: person,
                            notes: (payload.notes ?? []).count,
                            letters: (payload.letters ?? []).count,
                            restored: restored)
    }
}
