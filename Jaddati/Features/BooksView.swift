import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

/// The shelf. Books the user brought in, and the way to bring in another.
struct BooksView: View {
    let personId: UUID
    /// True when this is the Books tab itself rather than a push from a person,
    /// so the tab root does not draw a chevron that goes nowhere.
    var isTabRoot: Bool = false

    @EnvironmentObject private var library: Library
    @EnvironmentObject private var player: AudioPlayer
    @State private var showingPicker = false
    @State private var isImporting = false
    @State private var pendingDeletion: Book?
    @State private var errorText: String?
    @State private var openedBookId: UUID?

    private var person: Person? { library.person(withId: personId) }

    var body: some View {
        VStack(spacing: 0) {
            AppBar(title: L("Books"), showsBack: !isTabRoot)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    if let person {
                        Breadcrumb(name: person.name,
                                   relationship: person.relationship,
                                   photo: library.photoURL(for: person))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Headline(text: L("A shelf of\nfamiliar pages."))
                        SubText(text: L("Bring a text. Hear it in a recreated voice, one page at a time."))
                    }

                    if let errorText {
                        ErrorNote(message: errorText) { self.errorText = nil }
                    }

                    shelf

                    Button(isImporting ? L("Importing…") : L("Import book")) {
                        showingPicker = true
                    }
                    .buttonStyle(PrimaryButtonStyle(enabled: !isImporting))
                    .disabled(isImporting)

                    if isImporting {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(L("Importing…"))
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Palette.inkSoft)
                        }
                    }

                    Text(L("Only import text you have the right to have read aloud."))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Theme.Metric.screenPadding)
                .padding(.top, Theme.Space.s)
                .padding(.bottom, Theme.Space.xl)
            }
        }
        .background(Theme.Palette.paper)
        .navigationBarHidden(true)
        .navigationDestination(item: $openedBookId) { id in
            BookReaderView(bookId: id, personId: personId)
        }
        .confirmationDialog(L("Delete this book?"),
                            isPresented: Binding(get: { pendingDeletion != nil },
                                                 set: { if !$0 { pendingDeletion = nil } }),
                            titleVisibility: .visible) {
            Button(L("Delete book and its audio"), role: .destructive) {
                if let book = pendingDeletion {
                    player.stop()               // it may be reading this book
                    library.delete(book)
                }
                pendingDeletion = nil
            }
            Button(L("Cancel"), role: .cancel) { pendingDeletion = nil }
        } message: {
            Text(L("This removes the imported text and its generated page audio."))
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
                          title: L("No books yet"),
                          message: L("Your first book belongs here."))
            } else {
                // Keyed on the id, not the whole value: Book carries currentPage,
                // so turning a page changed its hash and tore down the row.
                ForEach(Array(books.enumerated()), id: \.element.id) { index, book in
                    HStack(alignment: .top, spacing: 16) {
                        // A book, drawn as a book. The cover alternates so a
                        // shelf of two reads as a shelf, not a list.
                        BookCover(title: book.title,
                                  tint: index % 2 == 0 ? Theme.Palette.coverGreen
                                                       : Theme.Palette.coverRust)

                        VStack(alignment: .leading, spacing: 7) {
                            BidiText(value: book.title,
                                     font: Theme.Font.display(22),
                                     colour: Theme.Palette.ink,
                                     lineLimit: 2)

                            Theme.Palette.hairline.frame(height: 1)

                            Text(Counts.pagesRead(library.pagesRead(of: book), of: book.pageCount))
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.Palette.inkSoft)

                            // Credits, not dollars: the reader one tap away
                            // quotes credits, and on a free tier credits are
                            // what runs out. The remaining pages, not the whole
                            // book — pages already read are paid for.
                            // An estimate, and said to be one: it assumes every
                            // remaining page is average length.
                            Text(L("Roughly") + " "
                                 + Counts.number(max(book.totalCharacters
                                                     * max(book.pageCount - library.pagesRead(of: book), 0)
                                                     / max(book.pageCount, 1), 0))
                                 + " " + L("credits left to read"))
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.Palette.inkSoft)

                            HStack {
                                Button(L("Open book")) { openedBookId = book.id }
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.Palette.wine)
                                Spacer()
                                // Visible, not hidden behind a long press.
                                Button { pendingDeletion = book } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 14))
                                        .foregroundStyle(Theme.Palette.inkSoft)
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(L("Delete book"))
                            }
                        }
                    }
                    .padding(.vertical, 12)
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
            errorText = L("That file could not be opened.")
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
                errorText = L("That file could not be read from its location.")
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
                            ?? L("That file could not be turned into pages.")
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
    /// False when the page WAS read and only the write to disk failed. Reading
    /// it again would pay the provider a second time for audio we already have,
    /// so that message arrives without a Try again button.
    @State private var errorAllowsRetry = true

    @State private var question = ""
    @State private var isAnswering = false
    @State private var answer: String?
    @State private var answerAsset: AudioAsset?
    @State private var questionError: String?
    /// As with the page above: an answer that was spoken and then failed to
    /// save must not offer a button that pays for it again.
    @State private var questionAllowsRetry = true
    /// How far into the page the story had got when it was interrupted, as a
    /// fraction. Playing the answer replaces the audio player, so the position
    /// is gone by the time the story is asked to carry on.
    @State private var resumeAt: Double?
    /// Answers made in this sitting. Kept so a new question can clear the one
    /// before it without waiting for the launch sweep.
    @State private var answerIds: [UUID] = []

    private var book: Book? { library.book(withId: bookId) }
    private var person: Person? { library.person(withId: personId) }
    private var pageText: String { book?.page(pageIndex) ?? "" }
    private var alreadyRead: AudioAsset? {
        guard let book else { return nil }
        return library.readPage(of: book, index: pageIndex)
    }

    var body: some View {
        VStack(spacing: 0) {
            AppBar(title: book?.title ?? L("Untitled book"))

            if let book {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        header(book)
                        pagePanel
                        if let errorText {
                            if errorAllowsRetry {
                                ErrorNote(message: errorText) {
                                    self.errorText = nil
                                    Task { await readPage() }
                                }
                            } else {
                                ErrorNote(message: errorText)
                            }
                        }
                        controls(book)
                        questionSection
                    }
                    .padding(Theme.Space.m)
                    .padding(.bottom, Theme.Space.xl)
                }
                .scrollDismissesKeyboard(.interactively)
            } else {
                EmptyHint(icon: "book.closed",
                          title: L("Book removed"),
                          message: L("This book is no longer on the phone."))
                Spacer(minLength: 0)
            }
        }
        .background(Theme.Palette.paper)
        .navigationBarHidden(true)
        .onAppear {
            // Clamped at both ends: a book with no pages would otherwise land
            // on index -1.
            if let book {
                pageIndex = max(0, min(book.currentPage, max(book.pageCount - 1, 0)))
            }
        }
        .onDisappear {
            player.stop()
            // Deliberately does NOT delete the answers made in this sitting.
            // Tapping a tab or flipping the language fires this, and doing so
            // destroyed audio the user had just paid for. They are stored
            // unkept, so Library.init sweeps them at the next launch.
        }
        .onChange(of: question) { old, new in
            // First keystroke stops the story. Waiting until "Ask" is tapped
            // meant the page carried on talking over the child.
            if old.isEmpty && !new.isEmpty { pauseForQuestion() }
        }
    }

    private func header(_ book: Book) -> some View {
        HStack {
            Text(Counts.pagePosition(pageIndex + 1, of: book.pageCount))
                .font(Theme.Font.label)
                .foregroundStyle(Theme.Palette.ink)
            Spacer()
            if alreadyRead != nil {
                Text(L("Page already read"))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.bronze)
            } else {
                Text("≈ " + Counts.number(pageText.count) + " " + L("credits"))
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
                .lineSpacing(Theme.textLineSpacing)
                .multilineTextAlignment(TextDirection.isArabic(pageText) ? .trailing : .leading)
                .frame(maxWidth: .infinity,
                       alignment: TextDirection.isArabic(pageText) ? .trailing : .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private func controls(_ book: Book) -> some View {
        if let asset = alreadyRead, library.fileExists(for: asset) {
            Button(player.isPlaying(assetId: asset.id) ? L("Pause") : L("Replay this page")) {
                player.play(url: library.url(for: asset), assetId: asset.id)
            }
            .buttonStyle(PrimaryButtonStyle())
        } else {
            Button(isGenerating ? L("Creating audio…") : L("Read this page")) {
                Task { await readPage() }
            }
            .buttonStyle(PrimaryButtonStyle(enabled: canRead))
            .disabled(!canRead)

            if !canRead && !isGenerating {
                // Name the thing that is actually missing. Inferring it from
                // hasVoice alone reported a key problem for an empty page.
                Text(!AppConfig.isConfigured
                     ? L("Voice service is not connected.")
                     : (person?.hasVoice == true
                        ? L("There is nothing on this page to read.")
                        : L("Add a voice before creating audio.")))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
        }

        HStack(spacing: Theme.Space.s) {
            Button(L("Previous page")) { move(by: -1, in: book) }
                .buttonStyle(QuietButtonStyle())
                .disabled(pageIndex == 0)
            Button(L("Next page")) { move(by: 1, in: book) }
                .buttonStyle(QuietButtonStyle())
                .disabled(pageIndex >= book.pageCount - 1)
        }

        Text(L("Page audio is an AI recreation of the voice.") + " " + L("Only import text you have the right to have read aloud."))
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Palette.inkSoft)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private var canRead: Bool {
        person?.hasVoice == true && AppConfig.isConfigured && !isGenerating
            && !pageText.isEmpty && !library.loadFailed
    }

    private func move(by delta: Int, in book: Book) {
        player.stop()
        pageIndex = max(0, min(max(pageIndex + delta, 0), book.pageCount - 1))
        errorText = nil
        clearQuestion()
        // Turning the page is the deliberate way to leave a question behind, so
        // its audio goes here rather than waiting for the launch sweep.
        discardAnswers()
        var updated = book
        updated.currentPage = pageIndex
        library.update(updated)
    }

    // MARK: Stopping to ask

    /// The interruption. A child stops the story, asks something, hears the
    /// answer in the same voice, and the story picks up where it stopped.
    @ViewBuilder private var questionSection: some View {
        if !AppConfig.isCompanionConfigured, person?.hasVoice == true {
            // Silently absent is indistinguishable from never built. Say which.
            Panel {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(L("Stop and ask"))
                        .font(Theme.Font.label)
                        .foregroundStyle(Theme.Palette.ink)
                    Text(L("Questions are not set up on this build."))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else if AppConfig.isCompanionConfigured, person?.hasVoice == true {
            Panel {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(L("Stop and ask"))
                        .font(Theme.Font.label)
                        .foregroundStyle(Theme.Palette.ink)

                    Text(L("Answers are written by AI. They are not their words and not their memories."))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)

                    askControls

                    if let answer { answerPanel(answer) }

                    if let questionError {
                        if questionAllowsRetry {
                            ErrorNote(message: questionError) {
                                self.questionError = nil
                                Task { await ask() }
                            }
                        } else {
                            ErrorNote(message: questionError)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var askControls: some View {
        TextField(L("What do you want to ask?"), text: $question, axis: .vertical)
            .font(Theme.Font.body)
            .foregroundStyle(Theme.Palette.ink)
            .lineLimit(1...3)
            .padding(Theme.Space.xs)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(Theme.Palette.ivorySunk)
            )
            .disabled(isAnswering)

        DictateButton(text: $question, prompt: L("Say the question instead"))

        Button(isAnswering ? L("Thinking…") : L("Ask")) {
            Task { await ask() }
        }
        .buttonStyle(PrimaryButtonStyle(enabled: canAsk))
        .disabled(!canAsk)
    }

    private func answerPanel(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            // The only audio in the app that had no badge on it, and the only
            // audio that starts playing before anyone has read anything.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    SourceBadge(isGenerated: true)
                    ContentBadge(provenance: .answerWhileReading)
                }
                VStack(alignment: .leading, spacing: 6) {
                    SourceBadge(isGenerated: true)
                    ContentBadge(provenance: .answerWhileReading)
                }
            }

            Text(text)
                .font(Theme.Font.spoken)
                .foregroundStyle(Theme.Palette.ink)
                .multilineTextAlignment(TextDirection.isArabic(text) ? .trailing : .leading)
                .frame(maxWidth: .infinity,
                       alignment: TextDirection.isArabic(text) ? .trailing : .leading)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Theme.Space.s) {
                if let answerAsset, library.fileExists(for: answerAsset) {
                    Button(player.isPlaying(assetId: answerAsset.id) ? L("Pause") : L("Hear it again")) {
                        player.play(url: library.url(for: answerAsset), assetId: answerAsset.id)
                    }
                    .buttonStyle(QuietButtonStyle())
                }
                if alreadyRead != nil {
                    Button(L("Continue the story")) { continueStory() }
                        .buttonStyle(QuietButtonStyle())
                }
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
        questionAllowsRetry = true
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
                                           provenance: L("A question asked while reading"),
                                           intent: .saySomething,
                                           content: .answerWhileReading,
                                           isSaved: false,
                                           fileExtension: CreateView.audioExtension(for: data))
            isAnswering = false
            if let asset {
                answerAsset = asset
                answerIds.append(asset.id)
                player.play(url: library.url(for: asset), assetId: asset.id)
            } else {
                questionAllowsRetry = false
                questionError = L("The answer was written but the audio could not be saved to this phone.")
            }
        } catch {
            isAnswering = false
            questionAllowsRetry = true
            questionError = (error as? CompanionError)?.errorDescription
                ?? (error as? VoiceServiceError)?.errorDescription
                ?? L("That question could not be answered. Try again.")
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
        errorAllowsRetry = true
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
                                           provenance: L("From your imported text") + " · " + Counts.pagePosition(index + 1, of: book.pageCount),
                                           intent: .readBook,
                                           content: .importedText,
                                           bookId: book.id,
                                           pageIndex: index,
                                           isSaved: true,
                                           fileExtension: CreateView.audioExtension(for: data))
            isGenerating = false
            if let asset {
                library.pruneDuplicatePages(of: book.id, index: index, keeping: asset.id)
                player.play(url: library.url(for: asset), assetId: asset.id)
            } else {
                errorAllowsRetry = false
                errorText = L("The page was read but the audio could not be saved to this phone.")
            }
        } catch {
            isGenerating = false
            let known = error as? VoiceServiceError
            errorAllowsRetry = !(known == .unauthorised
                                 || known == .outOfCredits
                                 || known == .voiceLimitReached
                                 || known == .notConfigured
                                 // The request was abandoned client-side after
                                 // 120s; the provider may well have finished it
                                 // and billed for it. Retrying pays twice.
                                 || known == .timedOut)
            errorText = known?.errorDescription
                ?? L("That page could not be read. Try again.")
        }
    }
}
