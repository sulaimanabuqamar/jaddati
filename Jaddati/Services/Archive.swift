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
/// original recordings, and that identifier.
///
/// Clips the family kept travel too, but ONLY into the cloud backup. Sharing
/// and backing up are not the same job. A shared file has to clear WhatsApp
/// and the relay's own ceiling, and at the other end a clip can simply be made
/// again — so sharing carries originals and nothing else, as it always has. A
/// backup is the answer to "the phone is gone, is she still there?", and there
/// a kept clip is not remade by regenerating it: the wording someone chose, the
/// day, and the reason they pressed keep do not come back. So `plan` takes a
/// flag, and only the backup sets it.
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

    /// ISO 8601, written by either platform.
    ///
    /// `.iso8601` is `ISO8601DateFormatter` with `.withInternetDateTime` and
    /// nothing else, and that rejects fractional seconds outright. The web
    /// stamps every date with `toISOString()`, which always has them. So an
    /// archive made in the browser failed on its FIRST date field, whatever
    /// else was right about it.
    ///
    /// The formatter is built inside the closure rather than held as a shared
    /// one. It runs a handful of times per archive, and a date formatter that
    /// two threads can reach is a class of bug not worth buying for that.
    static func archiveDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { input in
            let text = try input.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: text) { return date }
            throw DecodingError.dataCorrupted(.init(
                codingPath: input.codingPath,
                debugDescription: "Not an ISO 8601 date: \(text)"))
        }
        return decoder
    }

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
        /// Carried deliberately. Each family's Drive is their own, so there is
        /// no slot to collide with — and without it someone who arrived by
        /// code is invisible to the restore check, so restoring the same
        /// person from Drive stands a second copy of her beside the first.
        var cloudKey: String? = nil
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
        // Optional, all three, because the WEB writes them one level down
        // inside `asset` and does not write them here at all. Non-optional is
        // what made every archive the browser produced fail to decode on the
        // phone — and since `recordings` is an optional ARRAY rather than an
        // array of optionals, that one mismatch took the whole Payload with it
        // and the family were told the file was not a Jaddati archive.
        //
        // Read them through `spoken`, `seconds` and `suffix` below, never
        // directly.
        var text: String? = nil
        var durationSeconds: Double? = nil
        var promptId: String? = nil
        var fileExtension: String? = nil
        /// Base64. Large, but a family archive that needs a second file
        /// alongside it is one that arrives incomplete.
        var data: String

        // Everything below is optional, and absent means "a real recording".
        // Absent is what every archive written for sharing says, and what every
        // archive written before backup carried kept clips says. Optional is
        // also what lets an older build open a newer archive: keys it does not
        // know are ignored, and the clips land as recordings rather than the
        // whole file failing to open.

        /// `AudioSource.rawValue`.
        var source: String? = nil
        /// `Intent.rawValue` — which screen made the clip.
        var intent: String? = nil
        /// `ContentProvenance.rawValue` — where the words came from.
        var contentKind: String? = nil
        /// The authorship label shown with the clip. A fiction label that
        /// survives only until the clip is restored is not a label.
        var provenance: String? = nil
        var modelId: String? = nil
        /// The day it was made. Without it a restored clip claims it was made
        /// on the day it arrived — the same bug the letters above already
        /// carry a comment about.
        var createdAt: Date? = nil

        /// What the web puts here instead: the asset as it stores it, and a
        /// MIME type where this side writes a file extension. Never written by
        /// this platform, only read.
        var asset: WebAssetCard? = nil
        var type: String? = nil

        // One place each of these is decided, so no caller has to know which
        // platform wrote the file.
        var spoken: String { text ?? asset?.text ?? "" }
        var seconds: Double { durationSeconds ?? asset?.durationSeconds ?? 0 }
        var suffix: String {
            if let fileExtension, !fileExtension.isEmpty { return fileExtension }
            let mime = type ?? ""
            if mime.contains("wav") { return "wav" }
            if mime.contains("webm") { return "webm" }
            if mime.contains("mp4") || mime.contains("m4a") || mime.contains("aac") { return "m4a" }
            return "mp3"
        }
        /// Absent means a real recording, on either platform.
        var kind: AudioSource {
            (source ?? asset?.source).flatMap(AudioSource.init(rawValue:)) ?? .original
        }
        var made: Date? { createdAt ?? asset?.createdAt }
        var experience: String? { intent ?? asset?.intentRaw }
        var words: String? { contentKind ?? asset?.contentKind }
        var authorship: String? { provenance ?? asset?.provenance }
        var model: String? { modelId ?? asset?.modelId }
        var prompt: String? { promptId ?? asset?.promptId }
    }

    /// The web's shape for one recording's metadata. Decoded, never encoded,
    /// and every field optional — this is someone else's format and a missing
    /// key here must never cost the family the archive.
    struct WebAssetCard: Codable {
        var text: String? = nil
        var durationSeconds: Double? = nil
        var source: String? = nil
        var intentRaw: String? = nil
        var contentKind: String? = nil
        var provenance: String? = nil
        var modelId: String? = nil
        var createdAt: Date? = nil
        var promptId: String? = nil
    }

    struct ExportResult {
        let url: URL
        let carried: Int
        /// Of `carried`, how many were real recordings. The backup compares
        /// this against how many originals the person has before it overwrites
        /// what is already in Drive, so it has to be counted apart from the
        /// kept clips — otherwise a person with nine clips and one unreadable
        /// recording looks complete.
        let carriedOriginals: Int
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
        /// Kept clips. Empty unless the caller asked for them. Held apart from
        /// `originals` rather than mixed in, because the two are spent against
        /// the size budget in order and counted separately afterwards.
        var extras: [PlannedRecording] = []
    }

    /// One original recording, named by where it lives rather than by its
    /// bytes. The bytes are read during the build, off the main actor.
    struct PlannedRecording {
        var url: URL
        var text: String
        var durationSeconds: Double
        var promptId: String?
        var fileExtension: String

        // Carried through to RecordingCard. Defaulted, so the originals below
        // read exactly as they did before.
        var source: AudioSource = .original
        var intent: String? = nil
        var contentKind: String? = nil
        var provenance: String? = nil
        var modelId: String? = nil
        var createdAt: Date? = nil
    }

    /// Reads the library. Main actor only — see `ExportPlan`.
    @MainActor
    static func plan(person: Person, library: Library,
                     includingKeptClips: Bool = false) -> ExportPlan {
        ExportPlan(
            displayName: person.name,
            person: PersonCard(name: person.name,
                               fullName: person.fullName,
                               relationship: person.relationship,
                               voiceId: person.voiceId,
                               voiceCreatedAt: person.voiceCreatedAt,
                               voiceRequiresVerification: person.voiceRequiresVerification,
                               consentConfirmedAt: person.consentConfirmedAt,
                               tuning: person.tuning,
                               cloudKey: person.cloudKey),
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
                                 fileExtension: ($0.filename as NSString).pathExtension,
                                 createdAt: $0.createdAt)
            },
            // keptClips, not `isSaved`: book pages are stored saved so a page is
            // never paid for twice, and reading the flag directly would carry
            // the whole page cache of every imported book into the backup.
            extras: includingKeptClips
                ? library.keptClips(for: person).map {
                    PlannedRecording(url: library.url(for: $0),
                                     text: $0.text,
                                     durationSeconds: $0.durationSeconds,
                                     promptId: $0.promptId,
                                     fileExtension: ($0.filename as NSString).pathExtension,
                                     source: .generated,
                                     intent: $0.intentRaw,
                                     contentKind: $0.contentKind,
                                     provenance: $0.provenance,
                                     modelId: $0.modelId,
                                     createdAt: $0.createdAt)
                }
                : [])
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
        var carriedOriginals = 0

        // Originals first, always. The budget is spent on the irreplaceable
        // things before the ones that can be made again, and the backup's
        // "is this copy worse than the one already up there?" check reads the
        // original count — so a kept clip must never crowd a recording out.
        for asset in plan.originals + plan.extras {
            // One file's bytes and one file's base64 exist at a time inside
            // here. Without the pool the Foundation temporaries sit until the
            // whole loop ends, so every recording is resident at once.
            autoreleasepool {
                guard let data = try? Data(contentsOf: asset.url) else { unreadable += 1; return }
                let encoded = Int(Double(data.count) * base64Overhead)
                guard carried + encoded <= ceiling else { tooLarge += 1; return }
                carried += encoded
                if asset.source == .original { carriedOriginals += 1 }
                recordings.append(RecordingCard(
                    text: asset.text,
                    durationSeconds: asset.durationSeconds,
                    promptId: asset.promptId,
                    fileExtension: asset.fileExtension,
                    data: data.base64EncodedString(),
                    source: asset.source.rawValue,
                    intent: asset.intent,
                    contentKind: asset.contentKind,
                    provenance: asset.provenance,
                    modelId: asset.modelId,
                    createdAt: asset.createdAt))
            }
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
                            carriedOriginals: carriedOriginals,
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
        /// Files that would not READ, as opposed to would not fit. Different
        /// cause, different remedy, and dropping it meant a family could be
        /// told the code was ready while three recordings had quietly failed
        /// to travel — with nothing said at either end.
        let unreadable: Int
    }

    @MainActor
    static func send(person: Person, library: Library) async throws -> CodeResult {
        guard Consent.networkAllowed else { throw ConsentMissing() }

        // Read the library here, on the main actor, then hand the plain values
        // to another thread to do the megabytes of work. Done inline this froze
        // the screen for the whole export — long enough that "Preparing…" never
        // got drawn, so the app looked dead rather than busy.
        let outline = Self.plan(person: person, library: library)
        let (exported, body) = try await Task.detached(priority: .userInitiated) {
            () async throws -> (ExportResult, Data) in
            let built = try Archive.build(outline, ceiling: Archive.relayMaxBytes)
            // The temporary file has done its job the moment it is read. Left
            // behind, every handoff leaks another copy of the whole archive
            // into the container.
            defer { try? FileManager.default.removeItem(at: built.url) }
            let bytes = try Data(contentsOf: built.url)
            return (built, bytes)
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
                          carried: exported.carried, tooLarge: exported.tooLarge,
                          unreadable: exported.unreadable)
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
        let decoder = Self.archiveDecoder()

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
        person.cloudKey = card.cloudKey
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
            // Absent means a real recording. Hard-coding `.original` here is
            // what made a restored archive claim the clips it carried were
            // recordings of her — the one label in this app that must never be
            // wrong about which is which.
            let source = recording.kind
            // One unreadable recording must not cost the family the other nine.
            if var stored = library.storeAudio(data: bytes,
                                  for: person,
                                  source: source,
                                  text: recording.spoken,
                                  duration: recording.seconds,
                                  modelId: recording.model,
                                  provenance: recording.authorship,
                                  intent: recording.experience.flatMap(Intent.init(rawValue:)),
                                  content: recording.words.flatMap(ContentProvenance.init(rawValue:)),
                                  isSaved: true,
                                  promptId: recording.prompt,
                                  fileExtension: Self.safeExtension(recording.suffix)) {
                // storeAudio stamps "now", the same way addLetter did.
                if let made = recording.made {
                    stored.createdAt = made
                    library.update(stored)
                }
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
