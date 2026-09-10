import XCTest
@testable import Jaddati

/// Tests for the parts where being wrong is expensive: what the app claims
/// about a voice, what it claims about where words came from, and whether it
/// can lose someone's audio.
final class JaddatiTests: XCTestCase {

    // MARK: Voice readiness

    /// A voice id alone is not readiness. The provider can return one that
    /// cannot speak, and showing "Voice ready" for it produces a silent demo.
    func testVoiceIsNotReadyWhileVerificationIsPending() {
        var person = Person(name: "Jaddati")
        XCTAssertFalse(person.hasVoice)

        person.voiceId = "abc123"
        person.voiceRequiresVerification = true
        XCTAssertFalse(person.hasVoice, "a voice awaiting verification must not read as ready")
        XCTAssertTrue(person.voicePendingVerification)

        person.voiceRequiresVerification = false
        XCTAssertTrue(person.hasVoice)
        XCTAssertFalse(person.voicePendingVerification)
    }

    /// An index written before the verification field existed must still load.
    func testPersonDecodesFromAnIndexWrittenByAnEarlierBuild() throws {
        let legacy = """
        {"id":"\(UUID().uuidString)","name":"Jaddati","fullName":"","relationship":"",
         "createdAt":"2026-09-10T10:00:00Z"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let person = try decoder.decode(Person.self, from: Data(legacy.utf8))
        XCTAssertEqual(person.name, "Jaddati")
        XCTAssertNil(person.voiceRequiresVerification)
        XCTAssertFalse(person.hasVoice)
    }

    // MARK: Retelling — the honesty rule

    func testRetellingKeepsEveryNoteItClaimsToHaveUsed() {
        let id = UUID()
        let notes = (1...7).map { FamilyNote(personId: id, text: "Memory number \($0)") }
        let out = Composer.retelling(from: notes)
        let text = try! XCTUnwrap(out)

        for n in 1...7 {
            XCTAssertTrue(text.contains("Memory number \(n)"),
                          "note \(n) was dropped while still claiming to be the family's words")
        }
    }

    func testRetellingIsNilWithNothingToRetell() {
        XCTAssertNil(Composer.retelling(from: []))
        XCTAssertNil(Composer.retelling(from: [FamilyNote(personId: UUID(), text: "   ")]))
    }

    func testRetellingDoesNotDoublePunctuate() {
        let note = FamilyNote(personId: UUID(), text: "Did she really say that?")
        let text = try! XCTUnwrap(Composer.retelling(from: [note]))
        XCTAssertFalse(text.contains("?."), "a question mark should not gain a trailing period")
    }

    // MARK: Script detection

    func testArabicDetection() {
        XCTAssertTrue(TextDirection.isArabic("خذي وقتك يا حبيبتي"))
        XCTAssertTrue(TextDirection.isArabic("Take your time يا حبيبتي"))
        XCTAssertFalse(TextDirection.isArabic("Take your time"))
        XCTAssertFalse(TextDirection.isArabic(""))
        XCTAssertTrue(TextDirection.isArabic("\u{FEF3}"), "presentation forms must count as Arabic")
    }

    // MARK: Storage

    func testStoredAudioSurvivesAContainerPathChange() throws {
        let library = makeLibrary()
        let person = Person(name: "Jaddati")
        library.add(person)

        let asset = try XCTUnwrap(library.storeAudio(data: sampleBytes(),
                                                     for: person,
                                                     source: .original,
                                                     fileExtension: "m4a"))

        // The filename is what is persisted; the directory is resolved fresh.
        // iOS reassigns the container UUID on every install, so a stored
        // absolute path would be dangling after a reinstall.
        XCTAssertFalse(asset.filename.contains("/"),
                       "only a filename may be stored, never a path")
        XCTAssertTrue(library.fileExists(for: asset))
        XCTAssertTrue(library.url(for: asset).path.hasSuffix(asset.filename))
    }

    func testDeletingAnAssetRemovesItsFile() throws {
        let library = makeLibrary()
        let person = Person(name: "Jaddati")
        library.add(person)
        let asset = try XCTUnwrap(library.storeAudio(data: sampleBytes(), for: person, source: .generated))
        let url = library.url(for: asset)

        XCTAssertTrue(library.delete(asset))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(library.assets(for: person).isEmpty)
    }

    func testDeletingAPersonTakesTheirAudioWithThem() throws {
        let library = makeLibrary()
        let person = Person(name: "Jaddati")
        library.add(person)
        let original = try XCTUnwrap(library.storeAudio(data: sampleBytes(), for: person, source: .original))
        let generated = try XCTUnwrap(library.storeAudio(data: sampleBytes(), for: person, source: .generated))
        library.add(FamilyNote(personId: person.id, text: "She kept the door unlocked."))

        library.delete(person)

        XCTAssertTrue(library.people.isEmpty)
        XCTAssertTrue(library.notes(for: person).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: library.url(for: original).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: library.url(for: generated).path))
    }

    func testOriginalsAndGeneratedAudioStaySeparable() throws {
        let library = makeLibrary()
        let person = Person(name: "Jaddati")
        library.add(person)
        _ = library.storeAudio(data: sampleBytes(), for: person, source: .original)
        _ = library.storeAudio(data: sampleBytes(), for: person, source: .generated)

        XCTAssertEqual(library.assets(for: person, source: .original).count, 1)
        XCTAssertEqual(library.assets(for: person, source: .generated).count, 1)
        XCTAssertTrue(library.assets(for: person, source: .generated).allSatisfy { $0.isGenerated })
        XCTAssertFalse(library.assets(for: person, source: .original).contains { $0.isGenerated })
    }

    func testProvenanceIsStoredWithTheAudioNotDerivedLater() throws {
        let library = makeLibrary()
        let person = Person(name: "Jaddati")
        library.add(person)

        let asset = try XCTUnwrap(library.storeAudio(data: sampleBytes(),
                                                     for: person,
                                                     source: .generated,
                                                     text: "Once there was a lamp.",
                                                     provenance: "An invented story. Not a real memory."))
        // Reload from disk: the label must survive, or a fiction clip replayed
        // from the archive loses its disclaimer.
        let reloaded = Library(directoryName: library.testDirectoryName)
        let found = try XCTUnwrap(reloaded.assets.first { $0.id == asset.id })
        XCTAssertEqual(found.provenance, "An invented story. Not a real memory.")
    }

    // MARK: Failure wording

    func testEveryProviderFailureSaysSomethingUseful() {
        let cases: [VoiceServiceError] = [
            .notConfigured, .textTooLong(limit: 800), .sampleUnreadable,
            .sampleRejected(""), .unauthorised, .outOfCredits, .voiceLimitReached,
            .rateLimited, .offline, .timedOut, .provider(status: 500, detail: "x"), .badResponse
        ]
        for error in cases {
            let message = error.errorDescription ?? ""
            XCTAssertFalse(message.isEmpty, "\(error) has no message")
            XCTAssertFalse(message.contains("Optional("), "\(error) leaks Swift syntax at the user")
            XCTAssertFalse(message.contains("Error Domain"), "\(error) leaks a raw NSError")
        }
    }

    // MARK: Debug stand-in

    func testMockToneIsAPlayableWavAndNotSilence() {
        let data = MockVoiceService.tone(seconds: 1.0, sampleRate: 8_000)
        XCTAssertTrue(data.starts(with: Array("RIFF".utf8)))
        XCTAssertEqual(CreateView.audioExtension(for: data), "wav")
        XCTAssertEqual(CreateView.audioExtension(for: Data([0xFF, 0xFB, 0x00])), "mp3")
        XCTAssertGreaterThan(data.count, 8_000, "a second of 16-bit 8kHz audio should be ~16KB")
    }

    // MARK: Helpers

    private var createdDirectories: [String] = []

    private func makeLibrary() -> Library {
        let name = "JaddatiTests-\(UUID().uuidString)"
        createdDirectories.append(name)
        let library = Library(directoryName: name)
        library.testDirectoryName = name
        return library
    }

    private func sampleBytes() -> Data {
        Data(repeating: 0x41, count: 2_048)
    }

    override func tearDownWithError() throws {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask)[0]
        for name in createdDirectories {
            try? FileManager.default.removeItem(at: support.appendingPathComponent(name))
        }
        createdDirectories = []
    }
}
