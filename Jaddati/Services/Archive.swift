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
    ///
    /// Measured against the ENCODED size. Base64 is four bytes out for every
    /// three in, so budgeting raw bytes against this produced a file a third
    /// larger than the number it was checked against — and held both the string
    /// and the encoded Data in memory at once while doing it.
    static let maxBytes = 60 * 1024 * 1024

    /// The relay's own ceiling, which is lower — a KV value has a hard limit
    /// and the worker refuses anything above this. Building to 60 MB and then
    /// posting it meant the long wait happened first and the refusal came
    /// after, with nothing said about why. Kept in step with
    /// ARCHIVE_MAX_BYTES in proxy/src/worker.js.
    static let relayMaxBytes = 20 * 1024 * 1024

    private static let base64Overhead = 4.0 / 3.0

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
        let tooLarge: Int
        let unreadable: Int
    }

    enum Failure: LocalizedError {
        case notAnArchive
        case tooNew
        case empty
        case tooLargeForCode
        case codeNotFound
        case codeFailed
        case noConnection

        var errorDescription: String? {
            switch self {
            case .notAnArchive: return L("That file is not a Jaddati archive.")
            case .tooNew:       return L("That archive was made by a newer version of Jaddati. Update this one first.")
            case .empty:        return L("That archive has no one in it.")
            case .tooLargeForCode:
                return L("This archive is too large to send by code. Use the file instead.")
            case .codeNotFound:
                return L("No archive for that code. Codes last a day.")
            case .codeFailed:
                return L("That code could not be checked. Try again.")
            case .noConnection:
                return L("A code needs the internet. Use the file instead.")
            }
        }
    }

    // MARK: Out

    /// Everything the archive needs out of the library, as plain values.
    ///
    /// Split from the building on purpose. `Library` is an ObservableObject the
    /// UI owns, so it may only be read on the main actor — but the building is
    /// megabytes of file reading, base64 and JSON, and doing THAT on the main
    /// actor is a frozen screen behind a spinner that never gets drawn, because
    /// the thread that would draw it is busy. Gather on main, build off it.
    struct ExportPlan {
        var displayName: String
        var person: PersonCard
        var notes: [NoteCard]
        var letters: [LetterCard]
        var originals: [PlannedRecording]
    }

    /// One original recording, named by where it lives rather than by its
    /// bytes. The bytes are read during the build, off the main actor.
    struct PlannedRecording {
        var url: URL
        var text: String
        var durationSeconds: Double
        var promptId: String?
        var fileExtension: String
    }

    /// Reads the library. Main actor only — see `ExportPlan`.
    @MainActor
    static func plan(person: Person, library: Library) -> ExportPlan {
        ExportPlan(
            displayName: person.name,
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
            originals: library.assets(for: person, source: .original).map {
                PlannedRecording(url: library.url(for: $0),
                                 text: $0.text,
                                 durationSeconds: $0.durationSeconds,
                                 promptId: $0.promptId,
                                 fileExtension: ($0.filename as NSString).pathExtension)
            })
    }

    /// Writes the archive to a temporary file and hands back its URL, ready for
    /// the share sheet. The result says how many recordings actually fitted: a
    /// silent partial export would leave a family believing the recordings are
    /// safe on the other phone when they are not.
    ///
    /// Main actor, because gathering reads the library. The share sheet is the
    /// only caller and it is already there; `send` does the two halves apart so
    /// it can put the heavy one on another thread.
    @MainActor
    static func export(person: Person, library: Library) throws -> ExportResult {
        try build(plan(person: person, library: library))
    }

    /// The heavy half. Touches no app state, so it is safe anywhere — and
    /// belongs off the main actor.
    static func build(_ plan: ExportPlan, ceiling: Int = maxBytes) throws -> ExportResult {
        var recordings: [RecordingCard] = []
        // Two different reasons, kept apart: a file that would not fit is the
        // user's cue to send fewer, a file that would not READ is their cue to
        // go and look. Reporting both as "too large" sent people the wrong way.
        var carried = 0, tooLarge = 0, unreadable = 0

        for asset in plan.originals {
            guard let data = try? Data(contentsOf: asset.url) else { unreadable += 1; continue }
            let encoded = Int(Double(data.count) * base64Overhead)
            guard carried + encoded <= ceiling else { tooLarge += 1; continue }
            carried += encoded
            recordings.append(RecordingCard(
                text: asset.text,
                durationSeconds: asset.durationSeconds,
                promptId: asset.promptId,
                fileExtension: asset.fileExtension,
                data: data.base64EncodedString()))
        }

        let payload = Payload(
            jaddati: version,
            exportedAt: Date(),
            person: plan.person,
            notes: plan.notes,
            letters: plan.letters,
            recordings: recordings)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        // A name is not a filename: a slash in it makes the write throw.
        let stripped = plan.displayName.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>"))
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let safeName = stripped.isEmpty ? "jaddati" : stripped
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeName).jaddati.json")
        try data.write(to: file, options: .atomic)

        return ExportResult(url: file, carried: recordings.count,
                            tooLarge: tooLarge, unreadable: unreadable)
    }

    // MARK: By code

    /// Hand her over by code rather than by file.
    ///
    /// A file has to be found, attached, sent, found again and opened — five
    /// places a family can lose her, and the first four happen on a phone
    /// while someone stands next to you waiting. This puts the same bytes on
    /// the relay for a day and gives back six characters you can read aloud.
    ///
    /// Built on `export` and `importArchive` rather than beside them: the
    /// bytes, the size ceiling and every piece of validation are the ones
    /// already trusted, and a second copy of that logic would be a second
    /// thing to keep correct.
    struct CodeResult {
        let code: String
        let hours: Int
        let carried: Int
        let tooLarge: Int
    }

    @MainActor
    static func send(person: Person, library: Library) async throws -> CodeResult {
        guard Consent.networkAllowed else { throw ConsentMissing() }

        // Read the library here, on the main actor, then hand the plain values
        // to another thread to do the megabytes of work. Done inline this froze
        // the screen for the whole export — long enough that "Preparing…" never
        // got drawn, so the app looked dead rather than busy.
        let outline = Self.plan(person: person, library: library)
        let (exported, body) = try await Task.detached(priority: .userInitiated) { () -> (ExportResult, Data) in
            let built = try Archive.build(outline, ceiling: Archive.relayMaxBytes)
            // The temporary file has done its job the moment it is read. Left
            // behind, every handoff leaks another copy of the whole archive
            // into the container.
            defer { try? FileManager.default.removeItem(at: built.url) }
            return (built, try Data(contentsOf: built.url))
        }.value

        var request = URLRequest(url: URL(string: AppConfig.relayURL + "/archive")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        for (field, value) in AppConfig.relayHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.httpBody = body

        let (data, response) = try await send(request)
        guard let http = response as? HTTPURLResponse else { throw Failure.codeFailed }
        if http.statusCode == 413 { throw Failure.tooLargeForCode }
        guard http.statusCode == 200,
              let held = try? JSONDecoder().decode(HeldArchive.self, from: data) else {
            throw Failure.codeFailed
        }
        return CodeResult(code: held.code, hours: held.hours,
                          carried: exported.carried, tooLarge: exported.tooLarge)
    }

    @MainActor
    @discardableResult
    static func fetch(code: String, into library: Library) async throws -> ImportResult {
        guard Consent.networkAllowed else { throw ConsentMissing() }
        var request = URLRequest(url: URL(string: AppConfig.relayURL + "/archive/fetch")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        for (field, value) in AppConfig.relayHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.httpBody = try JSONEncoder().encode(["code": tidy(code)])

        let (data, response) = try await send(request)
        guard let http = response as? HTTPURLResponse else { throw Failure.codeFailed }
        // The same answer whether it never existed or has expired. The
        // difference is no use to whoever is typing, and saying which would
        // make codes worth guessing at.
        if http.statusCode == 404 { throw Failure.codeNotFound }
        guard http.statusCode == 200 else { throw Failure.codeFailed }

        // Through a file, so the arriving archive goes down exactly the path a
        // file from Files does — same decoding, same validation, same refusals.
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("incoming-\(UUID().uuidString).jaddati.json")
        try data.write(to: scratch, options: .atomic)
        defer { try? FileManager.default.removeItem(at: scratch) }
        return try importArchive(from: scratch, into: library)
    }

    private struct HeldArchive: Decodable {
        let code: String
        let hours: Int
    }

    /// Read aloud, so accept it typed back however it arrives.
    static func tidy(_ raw: String) -> String {
        raw.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do { return try await URLSession.shared.data(for: request) }
        catch let error as URLError
            where error.code == .notConnectedToInternet || error.code == .networkConnectionLost {
            throw Failure.noConnection
        }
    }

    // MARK: In

    struct ImportResult {
        let person: Person
        let notes: Int
        let letters: Int
        /// How many recordings the archive was carrying, and how many of those
        /// are now on this phone. Kept apart so the difference can be said out
        /// loud: "she arrived" over a silent loss is how a family finds out a
        /// year later that the recordings never came.
        let carried: Int
        let restored: Int

        var lost: Int { max(carried - restored, 0) }

        /// nil when everything arrived. Otherwise the sentence to show.
        var shortfall: String? {
            lost > 0 ? Counts.recordingsNotRead(lost) : nil
        }
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
            // Constructed here rather than through addLetter, which stamps
            // createdAt with "now". A letter that crossed to a second phone was
            // claiming it had been sealed on the day it arrived — a date then
            // baked permanently into the clip's provenance.
            var arrived = Letter(personId: person.id, text: letter.text,
                                 occasion: letter.occasion, deliverAt: letter.deliverAt)
            arrived.createdAt = letter.createdAt
            library.add(arrived)
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
                                  fileExtension: Self.safeExtension(recording.fileExtension)) != nil {
                restored += 1
            }
        }

        return ImportResult(person: person,
                            notes: (payload.notes ?? []).count,
                            letters: (payload.letters ?? []).count,
                            carried: (payload.recordings ?? []).count,
                            restored: restored)
    }

    /// An extension out of an untrusted file is interpolated into a filename.
    /// Only the handful the app itself writes are allowed through.
    static func safeExtension(_ raw: String) -> String {
        let allowed: Set<String> = ["m4a", "mp3", "wav", "webm", "caf", "aac"]
        let lowered = raw.lowercased()
        return allowed.contains(lowered) ? lowered : "m4a"
    }
}
