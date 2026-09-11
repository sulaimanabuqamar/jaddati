import Foundation
import Combine

/// Everything the app has stored: people, their audio, and family notes.
///
/// Persistence is deliberately plain — one JSON file for metadata, audio files
/// beside it on disk. No database, no migrations, nothing hidden. The whole
/// storage layer is readable in one sitting, which matters when we have to
/// explain it.
final class Library: ObservableObject {

    @Published private(set) var people: [Person] = []
    @Published private(set) var assets: [AudioAsset] = []
    @Published private(set) var notes: [FamilyNote] = []
    @Published private(set) var books: [Book] = []

    /// Set when loading or saving fails, so the UI can say so rather than
    /// silently pretending the save worked.
    @Published var storageError: String?

    /// True when the index existed but could not be decoded. Guards against the
    /// worst data-loss path there is: read fails, arrays are empty, the next
    /// save writes empty over the real file and the audio is orphaned forever.
    private(set) var loadFailed = false

    // MARK: Locations

    private let root: URL
    private let audioDir: URL
    private let photoDir: URL
    private var indexURL: URL { root.appendingPathComponent("library.json") }

    /// Only set by tests, so a second Library can be pointed at the same
    /// directory to prove that what was written is what comes back.
    var testDirectoryName: String = "Jaddati"

    init(directoryName: String = "Jaddati") {
        testDirectoryName = directoryName
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask)[0]
        root = support.appendingPathComponent(directoryName, isDirectory: true)
        audioDir = root.appendingPathComponent("Audio", isDirectory: true)
        photoDir = root.appendingPathComponent("Photos", isDirectory: true)
        createDirectoriesIfNeeded()
        load()
    }

    private func createDirectoriesIfNeeded() {
        for dir in [root, audioDir, photoDir] {
            if !FileManager.default.fileExists(atPath: dir.path) {
                try? FileManager.default.createDirectory(at: dir,
                                                         withIntermediateDirectories: true)
            }
        }
    }

    /// Resolve a stored filename to a real location, now.
    /// Never store the result — the container path changes between installs.
    func url(for asset: AudioAsset) -> URL {
        audioDir.appendingPathComponent(asset.filename)
    }

    /// Resolved fresh, like audio — a stored absolute path would dangle after
    /// the next install.
    func photoURL(for person: Person) -> URL? {
        guard let name = person.photoFilename else { return nil }
        let url = photoDir.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Writes a new photo, removes the old one, and records the filename.
    func setPhoto(_ data: Data, for person: Person) {
        let name = "\(UUID().uuidString).jpg"
        do {
            try data.write(to: photoDir.appendingPathComponent(name), options: .atomic)
        } catch {
            storageError = "That photo could not be saved to this phone."
            return
        }
        if let old = person.photoFilename {
            try? FileManager.default.removeItem(at: photoDir.appendingPathComponent(old))
        }
        var updated = person
        updated.photoFilename = name
        update(updated)
    }

    func removePhoto(for person: Person) {
        if let old = person.photoFilename {
            try? FileManager.default.removeItem(at: photoDir.appendingPathComponent(old))
        }
        var updated = person
        updated.photoFilename = nil
        update(updated)
    }

    func fileExists(for asset: AudioAsset) -> Bool {
        FileManager.default.fileExists(atPath: url(for: asset).path)
    }

    // MARK: Reading

    func assets(for person: Person, source: AudioSource? = nil) -> [AudioAsset] {
        assets
            .filter { $0.personId == person.id && (source == nil || $0.source == source!) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: Books

    func books(for person: Person) -> [Book] {
        books.filter { $0.personId == person.id }.sorted { $0.addedAt > $1.addedAt }
    }

    func book(withId id: UUID) -> Book? { books.first { $0.id == id } }

    func add(_ book: Book) {
        books.append(book)
        save()
    }

    func update(_ book: Book) {
        guard let i = books.firstIndex(where: { $0.id == book.id }) else { return }
        books[i] = book
        save()
    }

    /// Removes the book and every page already read from it.
    func delete(_ book: Book) {
        for asset in assets where asset.bookId == book.id {
            try? FileManager.default.removeItem(at: url(for: asset))
        }
        assets.removeAll { $0.bookId == book.id }
        books.removeAll { $0.id == book.id }
        save()
    }

    /// A page already generated. Found by id and index so it is replayed rather
    /// than paid for a second time.
    func readPage(of book: Book, index: Int) -> AudioAsset? {
        // `last`, not `first`: if a page was ever re-read, the newest row is the
        // one whose file exists. Returning the oldest left the reader stuck on a
        // broken row, offering to generate — and bill — the same page again.
        assets.last { $0.bookId == book.id && $0.pageIndex == index }
    }

    /// Drops earlier rows for a page that has just been re-read, so a book
    /// cannot accumulate orphaned duplicates.
    func pruneDuplicatePages(of bookId: UUID, index: Int, keeping keep: UUID) {
        let doomed = assets.filter { $0.bookId == bookId && $0.pageIndex == index && $0.id != keep }
        guard !doomed.isEmpty else { return }
        for asset in doomed { try? FileManager.default.removeItem(at: url(for: asset)) }
        assets.removeAll { asset in doomed.contains { $0.id == asset.id } }
        save()
    }

    func pagesRead(of book: Book) -> Int {
        Set(assets.compactMap { $0.bookId == book.id ? $0.pageIndex : nil }).count
    }

    // MARK: Saved lines

    /// Comfort lines the user added to the bank.
    func affirmations(for person: Person) -> [FamilyNote] {
        notes.filter { $0.personId == person.id && $0.isAffirmation }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Kept clips produced by one experience, newest first.
    func savedAssets(for person: Person, intent: Intent) -> [AudioAsset] {
        savedAssets(for: person, intents: [intent])
    }

    func savedAssets(for person: Person, intents: Set<Intent>) -> [AudioAsset] {
        let wanted = Set(intents.map(\.rawValue))
        return assets
            .filter {
                $0.personId == person.id && $0.isSaved
                    && ($0.intentRaw.map(wanted.contains) ?? false)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func notes(for person: Person) -> [FamilyNote] {
        notes.filter { $0.personId == person.id }.sorted { $0.createdAt < $1.createdAt }
    }

    func person(withId id: UUID) -> Person? {
        people.first { $0.id == id }
    }

    // MARK: Writing

    func add(_ person: Person) {
        people.append(person)
        save()
    }

    func update(_ person: Person) {
        guard let i = people.firstIndex(where: { $0.id == person.id }) else { return }
        people[i] = person
        save()
    }

    func add(_ note: FamilyNote) {
        notes.append(note)
        save()
    }

    func removeNote(_ note: FamilyNote) {
        notes.removeAll { $0.id == note.id }
        save()
    }

    /// Copy audio into our own storage and record it.
    /// `data` is written under a fresh filename so two imports never collide.
    @discardableResult
    func storeAudio(data: Data,
                    for person: Person,
                    source: AudioSource,
                    text: String = "",
                    duration: Double = 0,
                    modelId: String? = nil,
                    provenance: String? = nil,
                    intent: Intent? = nil,
                    content: ContentProvenance? = nil,
                    bookId: UUID? = nil,
                    pageIndex: Int? = nil,
                    isSaved: Bool = true,
                    fileExtension: String = "mp3") -> AudioAsset? {
        let name = "\(UUID().uuidString).\(fileExtension)"
        let destination = audioDir.appendingPathComponent(name)
        do {
            try data.write(to: destination, options: .atomic)
        } catch {
            storageError = "Could not save the audio to this phone. \(error.localizedDescription)"
            return nil
        }
        var asset = AudioAsset(personId: person.id,
                               source: source,
                               filename: name,
                               text: text,
                               durationSeconds: duration,
                               modelId: modelId)
        asset.isSaved = isSaved
        asset.provenance = provenance
        asset.intentRaw = intent?.rawValue
        // Falls back to the experience's own label rather than nil, so a clip is
        // never filed without a content provenance.
        asset.contentKind = (content ?? intent?.defaultContentProvenance)?.rawValue
        asset.bookId = bookId
        asset.pageIndex = pageIndex
        assets.append(asset)
        save()
        return asset
    }

    func update(_ asset: AudioAsset) {
        guard let i = assets.firstIndex(where: { $0.id == asset.id }) else { return }
        assets[i] = asset
        save()
    }

    /// Deletes the row and the file. Returns false if the file could not be
    /// removed, so the caller can tell the truth about what actually happened.
    @discardableResult
    func delete(_ asset: AudioAsset) -> Bool {
        let fileURL = url(for: asset)
        var fileRemoved = true
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do { try FileManager.default.removeItem(at: fileURL) }
            catch { fileRemoved = false }
        }
        assets.removeAll { $0.id == asset.id }
        save()
        return fileRemoved
    }

    /// Removes a person, their notes, and every file belonging to them.
    /// Does NOT remove the voice from the provider — the caller is responsible
    /// for saying so plainly in the UI.
    func delete(_ person: Person) {
        for asset in assets(for: person) {
            let fileURL = url(for: asset)
            try? FileManager.default.removeItem(at: fileURL)
        }
        if let photo = person.photoFilename {
            try? FileManager.default.removeItem(at: photoDir.appendingPathComponent(photo))
        }
        assets.removeAll { $0.personId == person.id }
        notes.removeAll { $0.personId == person.id }
        books.removeAll { $0.personId == person.id }
        people.removeAll { $0.id == person.id }
        save()
    }

    // MARK: Disk

    private struct Index: Codable {
        var people: [Person]
        var assets: [AudioAsset]
        var notes: [FamilyNote]
        /// Optional so an index written before books existed still decodes.
        var books: [Book]? = nil
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return }
        do {
            let data = try Data(contentsOf: indexURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let index = try decoder.decode(Index.self, from: data)
            people = index.people
            assets = index.assets
            notes = index.notes
            books = index.books ?? []
        } catch {
            // A corrupt index must not wedge the app on launch, and must not be
            // overwritten by the next save. Move it aside first, so the data is
            // recoverable, then start from an empty list.
            let backup = root.appendingPathComponent(
                "library.corrupt-\(Int(Date().timeIntervalSince1970)).json")
            do {
                try FileManager.default.moveItem(at: indexURL, to: backup)
                // The unreadable file is now safely aside under its own name, so
                // saving a fresh index destroys nothing and the app stays usable.
                storageError = "Saved memories could not be read, so they have been set aside rather than overwritten. The audio files are still on this phone."
            } catch {
                // The move failed, so the unreadable file is STILL at indexURL.
                // Saving now would write an empty index straight over it and
                // orphan every recording permanently. Refuse to write at all.
                loadFailed = true
                storageError = "Saved memories could not be read and could not be set aside, so nothing new will be saved until this is resolved. No audio has been deleted."
            }
        }
    }

    private func save() {
        // Set only when an unreadable index could NOT be moved aside, meaning
        // the real file is still sitting at indexURL. Writing then would put an
        // empty index over it and orphan every recording for good.
        guard !loadFailed else { return }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(
                Index(people: people, assets: assets, notes: notes, books: books))
            try data.write(to: indexURL, options: .atomic)
            storageError = nil
        } catch {
            storageError = "Changes could not be saved. \(error.localizedDescription)"
        }
    }
}
