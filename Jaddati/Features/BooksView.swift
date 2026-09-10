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
    @State private var pendingDeletion: Book?
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
        .confirmationDialog("Delete this book?",
                            isPresented: Binding(get: { pendingDeletion != nil },
                                                 set: { if !$0 { pendingDeletion = nil } }),
                            titleVisibility: .visible) {
            Button("Delete book and its audio", role: .destructive) {
                if let book = pendingDeletion {
                    player.stop()               // it may be reading this book
                    library.delete(book)
                }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("The pages you have already had read will be removed from this phone too.")
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
                    Panel {
                        HStack(alignment: .top, spacing: Theme.Space.s) {
                            Button { openedBookId = book.id } label: {
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
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            // Visible, not hidden behind a long press.
                            Button { pendingDeletion = book } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Theme.Palette.inkSoft)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Delete \(book.title)")
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

            // The title must come from the file the USER picked. Reading it
            // from `temp` produced book titles that were raw UUIDs.
            let displayName = url.deletingPathExtension().lastPathComponent
            let personId = person.id
            isImporting = true
            errorText = nil

            Task {
                let outcome = await Task.detached(priority: .userInitiated) { () -> ImportOutcome in
                    do {
                        let book = try BookImporter.makeBook(from: temp,
                                                             personId: personId,
                                                             displayName: displayName)
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

    @State private var question = ""
    @State private var isAnswering = false
    @State private var answer: String?
    @State private var answerAsset: AudioAsset?
    @State private var questionError: String?
    /// How far into the page the story had got when it was interrupted, as a
    /// fraction. Playing the answer replaces the audio player, so the position
    /// is gone by the time the story is asked to carry on.
    @State private var resumeAt: Double?
    /// Answers made in this sitting, so they can be cleared on the way out
    /// rather than piling up as files nothing lists.
    @State private var answerIds: [UUID] = []

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
                        questionSection
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
        .onDisappear {
            player.stop()
            discardAnswers()
        }
        .onChange(of: question) { old, new in
            // First keystroke stops the story. Waiting until "Ask" is tapped
            // meant the page carried on talking over the child.
            if old.isEmpty && !new.isEmpty { pauseForQuestion() }
        }
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
        clearQuestion()
        var updated = book
        updated.currentPage = pageIndex
        library.update(updated)
    }

    // MARK: Stopping to ask

    /// The interruption. A child stops the story, asks something, hears the
    /// answer in the same voice, and the story picks up where it stopped.
    @ViewBuilder private var questionSection: some View {
        if AppConfig.isCompanionConfigured, person?.hasVoice == true {
            Panel {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text("Stop and ask")
                        .font(Theme.Font.label)
                        .foregroundStyle(Theme.Palette.ink)

                    askControls

                    if let answer { answerPanel(answer) }

                    if let questionError {
                        ErrorNote(message: questionError) {
                            self.questionError = nil
                            Task { await ask() }
                        }
                    }

                    Text("Answers are written by AI. They are not their words and not their memories.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder private var askControls: some View {
        TextField("What do you want to ask?", text: $question, axis: .vertical)
            .font(Theme.Font.body)
            .foregroundStyle(Theme.Palette.ink)
            .lineLimit(1...3)
            .padding(Theme.Space.xs)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(Theme.Palette.ivorySunk)
            )
            .disabled(isAnswering)

        Button(isAnswering ? "Thinking\u{2026}" : "Ask") {
            Task { await ask() }
        }
        .buttonStyle(PrimaryButtonStyle(enabled: canAsk))
        .disabled(!canAsk)
    }

    private func answerPanel(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(text)
                .font(Theme.Font.spoken)
                .foregroundStyle(Theme.Palette.ink)
                .multilineTextAlignment(TextDirection.isArabic(text) ? .trailing : .leading)
                .frame(maxWidth: .infinity,
                       alignment: TextDirection.isArabic(text) ? .trailing : .leading)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Theme.Space.s) {
                if let answerAsset, library.fileExists(for: answerAsset) {
                    Button(player.isPlaying(assetId: answerAsset.id) ? "Pause" : "Hear it again") {
                        player.play(url: library.url(for: answerAsset), assetId: answerAsset.id)
                    }
                    .buttonStyle(QuietButtonStyle())
                }
                Button("Continue the story") { continueStory() }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(alreadyRead == nil)
            }
        }
        .padding(.top, Theme.Space.xs)
    }

    private var canAsk: Bool {
        !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isAnswering && !isGenerating
            && person?.hasVoice == true
            && AppConfig.isConfigured
            && AppConfig.isCompanionConfigured
    }

    private func pauseForQuestion() {
        guard let asset = alreadyRead, player.isPlaying(assetId: asset.id) else { return }
        resumeAt = player.duration > 0 ? player.currentTime / player.duration : 0
        player.pause()
    }

    private func continueStory() {
        clearQuestion()
        guard let asset = alreadyRead, library.fileExists(for: asset) else { return }
        player.ensurePlaying(url: library.url(for: asset), assetId: asset.id)
        if let mark = resumeAt, mark > 0, mark < 1 { player.seek(toProgress: mark) }
        resumeAt = nil
    }

    private func clearQuestion() {
        question = ""
        answer = nil
        answerAsset = nil
        questionError = nil
    }

    private func discardAnswers() {
        guard let person else { return }
        let doomed = library.assets(for: person, source: .generated)
            .filter { answerIds.contains($0.id) }
        for asset in doomed { _ = library.delete(asset) }
        answerIds = []
    }

    private func ask() async {
        let asked = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let book, let person, let voiceId = person.voiceId, canAsk else { return }

        pauseForQuestion()
        isAnswering = true
        questionError = nil
        answer = nil
        answerAsset = nil

        do {
            let reply = try await AppConfig.storyCompanion().answer(
                question: asked,
                page: PageContext(bookTitle: book.title,
                                  pageText: String(pageText.prefix(1_200)),
                                  pageNumber: pageIndex + 1))
            answer = reply

            let data = try await AppConfig.voiceService().synthesize(
                text: reply,
                voiceId: voiceId,
                modelId: AppConfig.defaultModelId,
                tuning: person.voiceTuning)
            let duration = (try? AVAudioPlayer(data: data))?.duration ?? 0

            // bookId and pageIndex stay nil deliberately. `readPage` matches on
            // exactly those two, so an answer filed against the page would be
            // handed back later as the page's own reading.
            let asset = library.storeAudio(data: data,
                                           for: person,
                                           source: .generated,
                                           text: reply,
                                           duration: duration,
                                           modelId: AppConfig.defaultModelId,
                                           provenance: "Answered a question while reading \(book.title).",
                                           intent: .saySomething,
                                           isSaved: false,
                                           fileExtension: CreateView.audioExtension(for: data))
            isAnswering = false
            if let asset {
                answerAsset = asset
                answerIds.append(asset.id)
                player.play(url: library.url(for: asset), assetId: asset.id)
            } else {
                questionError = "The answer was written but the audio could not be saved to this phone."
            }
        } catch {
            isAnswering = false
            questionError = (error as? CompanionError)?.errorDescription
                ?? (error as? VoiceServiceError)?.errorDescription
                ?? "That question could not be answered. Try again."
        }
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
