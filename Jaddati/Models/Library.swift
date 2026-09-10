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

    /// Set when loading or saving fails, so the UI can say so rather than
    /// silently pretending the save worked.
    @Published var storageError: String?

    // MARK: Locations

    private let root: URL
    private let audioDir: URL
    private var indexURL: URL { root.appendingPathComponent("library.json") }

    init(directoryName: String = "Jaddati") {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask)[0]
        root = support.appendingPathComponent(directoryName, isDirectory: true)
        audioDir = root.appendingPathComponent("Audio", isDirectory: true)
        createDirectoriesIfNeeded()
        load()
    }

    private func createDirectoriesIfNeeded() {
        for dir in [root, audioDir] {
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

    func fileExists(for asset: AudioAsset) -> Bool {
        FileManager.default.fileExists(atPath: url(for: asset).path)
    }

    // MARK: Reading

    func assets(for person: Person, source: AudioSource? = nil) -> [AudioAsset] {
        assets
            .filter { $0.personId == person.id && (source == nil || $0.source == source!) }
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
                    fileExtension: String = "mp3") -> AudioAsset? {
        let name = "\(UUID().uuidString).\(fileExtension)"
        let destination = audioDir.appendingPathComponent(name)
        do {
            try data.write(to: destination, options: .atomic)
        } catch {
            storageError = "Could not save the audio to this phone. \(error.localizedDescription)"
            return nil
        }
        let asset = AudioAsset(personId: person.id,
                               source: source,
                               filename: name,
                               text: text,
                               durationSeconds: duration,
                               modelId: modelId)
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
        assets.removeAll { $0.personId == person.id }
        notes.removeAll { $0.personId == person.id }
        people.removeAll { $0.id == person.id }
        save()
    }

    // MARK: Disk

    private struct Index: Codable {
        var people: [Person]
        var assets: [AudioAsset]
        var notes: [FamilyNote]
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
        } catch {
            // A corrupt index must not wedge the app on launch. Keep the audio,
            // surface the problem, start from an empty list.
            storageError = "Saved memories could not be read. The audio files are still on this phone."
        }
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(Index(people: people, assets: assets, notes: notes))
            try data.write(to: indexURL, options: .atomic)
            storageError = nil
        } catch {
            storageError = "Changes could not be saved. \(error.localizedDescription)"
        }
    }
}
