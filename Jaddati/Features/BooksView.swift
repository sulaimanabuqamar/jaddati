import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

/// The shelf. Books the user brought in, and the way to bring in another.
struct BooksView: View {
    let personId: UUID

    @EnvironmentObject private var library: Library
    @EnvironmentObject private var player: AudioPlayer
    @State private var showingPicker = false
    @State private var isImporting = false
    @State private var errorText: String?
    @State private var openedBookId: UUID?

    private var person: Person? { library.person(withId: personId) }

    var body: some View {
        ZStack {
            Theme.Palette.ivory.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Read me a book")
                            .font(Theme.Font.title)
                            .foregroundStyle(Theme.Palette.ink)
                        Text("A page at a time, so it never runs away with your credits.")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Palette.inkSoft)
                    }

                    if let errorText {
                        ErrorNote(message: errorText) { self.errorText = nil }
                    }

                    shelf

                    Button(isImporting ? "Reading the file…" : "Import a book") {
                        showingPicker = true
                    }
                    .buttonStyle(PrimaryButtonStyle(enabled: !isImporting))
                    .disabled(isImporting)

                    if isImporting {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Splitting it into pages. Nothing is generated yet.")
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Palette.inkSoft)
                        }
                    }

                    Text("Bring a plain text file or a PDF you have the right to have read aloud — something you wrote, or a text that is out of copyright. A scanned PDF has no text inside it, so it cannot be read.")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Theme.Space.m)
                .padding(.bottom, Theme.Space.xl)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openedBookId) { id in
            BookReaderView(bookId: id, personId: personId)
        }
        .fileImporter(isPresented: $showingPicker,
                      // Deliberately NOT `.text`: that is the parent type and
                      // also matches RTF, HTML, CSV and source files, whose
                      // markup would be read aloud and billed as words.
                      allowedContentTypes: [.plainText, .pdf],
                      allowsMultipleSelection: false) { result in
            handleImport(result)
        }
    }

    @ViewBuilder private var shelf: some View {
        if let person {
            let books = library.books(for: person)
            if books.isEmpty {
                EmptyHint(icon: "books.vertical",
                          title: "No books yet",
                          message: "Import something short to start with — a chapter, a letter, a story you wrote.")
            } else {
                ForEach(books) { book in
                    Button { openedBookId = book.id } label: {
                        Panel {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(book.title)
                                    .font(Theme.Font.heading)
                                    .foregroundStyle(Theme.Palette.ink)
                                    .multilineTextAlignment(.leading)
                                Text("\(book.pageCount) pages · \(library.pagesRead(of: book)) already read")
                                    .font(Theme.Font.caption)
                                    .foregroundStyle(Theme.Palette.inkSoft)
                                Text("About \(book.totalCharacters.formatted()) credits to read all of it")
                                    .font(Theme.Font.caption)
                                    .foregroundStyle(Theme.Palette.bronze)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            player.stop()          // it may be reading this book
                            library.delete(book)
                        } label: {
                            Label("Delete book and its audio", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    /// The outcome of parsing, carried back from a background task.
    private struct ImportOutcome: Sendable {
        let book: Book?
        let message: String?
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            if (error as? CocoaError)?.code == .userCancelled { return }
            errorText = "That file could not be opened."
        case .success(let urls):
            guard let url = urls.first, let person else { return }

            // Copy out under the security scope, then do the slow work off the
            // main thread. Extracting a PDF and running three regex passes over
            // it froze the screen for seconds with no sign of life.
            let scoped = url.startAccessingSecurityScopedResource()
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(url.pathExtension.isEmpty ? "txt" : url.pathExtension)
            do {
                try FileManager.default.copyItem(at: url, to: temp)
            } catch {
                if scoped { url.stopAccessingSecurityScopedResource() }
                errorText = "That file could not be read from its location."
                return
            }
            if scoped { url.stopAccessingSecurityScopedResource() }

            let personId = person.id
            isImporting = true
            errorText = nil

            Task {
                let outcome = await Task.detached(priority: .userInitiated) { () -> ImportOutcome in
                    do {
                        let book = try BookImporter.makeBook(from: temp, personId: personId)
                        return ImportOutcome(book: book, message: nil)
                    } catch {
                        let message = (error as? BookImporter.ImportError)?.errorDescription
                            ?? "That file could not be turned into pages."
                        return ImportOutcome(book: nil, message: message)
                    }
                }.value

                try? FileManager.default.removeItem(at: temp)
                isImporting = false
                if let book = outcome.book {
                    library.add(book)
                } else {
                    errorText = outcome.message
                }
            }
        }
    }
}

/// One book, one page at a time. A page already read is replayed for free; a
/// new one shows what it will cost before anything is spent.
struct BookReaderView: View {
    let bookId: UUID
    let personId: UUID

    @EnvironmentObject private var library: Library
    @EnvironmentObject private var player: AudioPlayer

    @State private var pageIndex: Int = 0
    @State private var isGenerating = false
    @State private var errorText: String?

    private var book: Book? { library.book(withId: bookId) }
    private var person: Person? { library.person(withId: personId) }
    private var pageText: String { book?.page(pageIndex) ?? "" }
    private var alreadyRead: AudioAsset? {
        guard let book else { return nil }
        return library.readPage(of: book, index: pageIndex)
    }

    var body: some View {
        ZStack {
            Theme.Palette.ivory.ignoresSafeArea()

            if let book {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        header(book)
                        pagePanel
                        if let errorText {
                            ErrorNote(message: errorText) {
                                self.errorText = nil
                                Task { await readPage() }
                            }
                        }
                        controls(book)
                    }
                    .padding(Theme.Space.m)
                    .padding(.bottom, Theme.Space.xl)
                }
            } else {
                EmptyHint(icon: "book.closed",
                          title: "Removed",
                          message: "This book is no longer on the phone.")
            }
        }
        .navigationTitle(book?.title ?? "Book")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Clamped at both ends: a book with no pages would otherwise land
            // on index -1.
            if let book {
                pageIndex = max(0, min(book.currentPage, max(book.pageCount - 1, 0)))
            }
        }
        .onDisappear { player.stop() }
    }

    private func header(_ book: Book) -> some View {
        HStack {
            Text("Page \(pageIndex + 1) of \(book.pageCount)")
                .font(Theme.Font.label)
                .foregroundStyle(Theme.Palette.ink)
            Spacer()
            if alreadyRead != nil {
                Text("Already read")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.bronze)
            } else {
                Text("≈ \(pageText.count) credits")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
        }
    }

    private var pagePanel: some View {
        Panel {
            Text(pageText)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.ink)
                .multilineTextAlignment(TextDirection.isArabic(pageText) ? .trailing : .leading)
                .frame(maxWidth: .infinity,
                       alignment: TextDirection.isArabic(pageText) ? .trailing : .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private func controls(_ book: Book) -> some View {
        if let asset = alreadyRead, library.fileExists(for: asset) {
            Button(player.isPlaying(assetId: asset.id) ? "Pause" : "Play this page") {
                player.play(url: library.url(for: asset), assetId: asset.id)
            }
            .buttonStyle(PrimaryButtonStyle())
        } else {
            Button(isGenerating ? "Reading…" : "Read this page") {
                Task { await readPage() }
            }
            .buttonStyle(PrimaryButtonStyle(enabled: canRead))
            .disabled(!canRead)

            if !canRead && !isGenerating {
                // Name the thing that is actually missing. Inferring it from
                // hasVoice alone reported a key problem for an empty page.
                Text(!AppConfig.isConfigured
                     ? "Voices aren't set up on this build."
                     : (person?.hasVoice == true
                        ? "There is nothing on this page to read."
                        : "This person has no usable voice yet."))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
        }

        HStack(spacing: Theme.Space.s) {
            Button("Previous") { move(by: -1, in: book) }
                .buttonStyle(QuietButtonStyle())
                .disabled(pageIndex == 0)
            Button("Next") { move(by: 1, in: book) }
                .buttonStyle(QuietButtonStyle())
                .disabled(pageIndex >= book.pageCount - 1)
        }

        Text("Only the page you ask for is generated. Nothing is read ahead.")
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Palette.inkSoft)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private var canRead: Bool {
        person?.hasVoice == true && AppConfig.isConfigured && !isGenerating && !pageText.isEmpty
    }

    private func move(by delta: Int, in book: Book) {
        player.stop()
        pageIndex = max(0, min(max(pageIndex + delta, 0), book.pageCount - 1))
        errorText = nil
        var updated = book
        updated.currentPage = pageIndex
        library.update(updated)
    }

    private func readPage() async {
        guard let book, let person, let voiceId = person.voiceId, canRead else { return }

        // A row whose file went missing used to bring this button back, and
        // every press billed the page again while the reader stayed stuck on
        // the broken row. Play what exists instead.
        if let existing = alreadyRead, library.fileExists(for: existing) {
            player.play(url: library.url(for: existing), assetId: existing.id)
            return
        }

        isGenerating = true
        errorText = nil
        let words = pageText
        let index = pageIndex

        do {
            let data = try await AppConfig.voiceService().synthesize(
                text: words,
                voiceId: voiceId,
                modelId: AppConfig.defaultModelId,
                tuning: person.voiceTuning)
            let duration = (try? AVAudioPlayer(data: data))?.duration ?? 0
            let asset = library.storeAudio(data: data,
                                           for: person,
                                           source: .generated,
                                           text: words,
                                           duration: duration,
                                           modelId: AppConfig.defaultModelId,
                                           provenance: "Read from your file, page \(index + 1).",
                                           intent: .readBook,
                                           bookId: book.id,
                                           pageIndex: index,
                                           isSaved: true,
                                           fileExtension: CreateView.audioExtension(for: data))
            isGenerating = false
            if let asset {
                library.pruneDuplicatePages(of: book.id, index: index, keeping: asset.id)
                player.play(url: library.url(for: asset), assetId: asset.id)
            } else {
                errorText = "The page was read but the audio could not be saved to this phone."
            }
        } catch {
            isGenerating = false
            errorText = (error as? VoiceServiceError)?.errorDescription
                ?? "That page could not be read. Try again."
        }
    }
}
