import DogearCore
import SwiftUI
import TipKit

struct LibraryView: View {
    let library: Library
    /// False while the Server refuses the refresh token or can't be reached; a change reloads the list.
    let canSync: Bool
    /// Chosen in the sidebar.
    @Binding var scope: BookScope
    /// Shared with the sidebar, which lists the libraries and shelves.
    @Binding var navigation: Navigation

    @State private var books: [Book] = []
    @State private var search = ""
    @State private var kind = BookKind.all
    @State private var hasLoaded = false
    @State private var problem: RequestError?
    @State private var reading: OpenBookFile?
    /// The Book pulled off the shelf to look at its catalog card.
    @State private var pulled: Book?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.palette) private var palette
    @State private var downloadProblem: String?
    @State private var coverColors = CoverColors()
    /// The scroll view's width, which decides how many spines and cases a shelf holds.
    @State private var width: CGFloat = 0
    @Environment(AppModel.self) private var model

    /// Between the screen's edge and the header controls and shelf contents.
    static let inset: CGFloat = 16
    private static let spineGap: CGFloat = 3
    private static let caseGap: CGFloat = 8
    private static let caseMinWidth: CGFloat = 150

    private var query: Query { Query(scope: scope, search: search, kind: kind) }

    /// Books with an ebook file stand on the shelves; an unsupported one still has its place.
    private var ebooks: [Book] {
        kind == .audiobooks ? [] : books.filter { $0.files.contains { $0.format != .audiobook } }
    }

    /// Books with an audiobook file sit in cassette cases. A Book with both is in both.
    private var audiobooks: [Book] {
        kind == .ebooks ? [] : books.filter { $0.files.contains { $0.format == .audiobook } }
    }

    /// The width inside the insets, where Books stand.
    private var shelfWidth: CGFloat { max(width - 2 * Self.inset, 0) }

    /// At accessibility text sizes a shelf would hold one Book, so each gets a row instead.
    private var usesRows: Bool { typeSize.isAccessibilitySize }

    var body: some View {
        let shelved = ebooks
        let racked = audiobooks
        // Looked up per Book file below, so each spine doesn't search every Position and Download.
        let shelving = ShelvingLookup(positions: model.recordedPositions, downloads: model.downloadList)
        let continuing = showsContinueRows ? model.continueRows.entries(showing: kind) : []
        let headed = !shelved.isEmpty && !racked.isEmpty
        ScrollView {
            // Every shelf is its own lazy row, so a large library only builds what's on screen.
            LazyVStack(spacing: 0) {
                header
                    .padding(.horizontal, Self.inset)
                    .padding(.bottom, 16)
                if let problem, let message = problem.errorDescription {
                    PaperTag(edge: Theme.ribbon) {
                        HStack {
                            Label(message, systemImage: "wifi.exclamationmark")
                                .font(.footnote)
                                .foregroundStyle(palette.ink)
                            Spacer(minLength: 8)
                            Button("Retry") { Task { await refresh() } }
                                .buttonStyle(OutlinedActionStyle(onPaper: true, fillsWidth: false))
                        }
                    }
                    .padding(.horizontal, Self.inset)
                    .padding(.bottom, 16)
                }
                if !shelved.isEmpty || !racked.isEmpty {
                    TipView(CatalogCardTip())
                        .tipBackground(palette.raised)
                        .tint(palette.paperAction)
                        // Paper is light whatever the theme.
                        .environment(\.colorScheme, .light)
                        .padding(.horizontal, Self.inset)
                        .padding(.bottom, 16)
                }
                if hasLoaded, books.isEmpty, problem == nil {
                    emptyState
                        .padding(.horizontal, Self.inset)
                        .padding(.vertical, 24)
                } else if !hasLoaded, books.isEmpty {
                    ProgressView()
                        .padding(.vertical, 40)
                }
                if !continuing.isEmpty {
                    continueShelf(continuing)
                }
                if !shelved.isEmpty {
                    if headed { headingShelf("Books") }
                    if usesRows {
                        ForEach(shelved) { book in
                            BookRow(book: book, isAudiobook: false, throughBook: shelving.throughBook(book), library: library)
                                .shelved(open: readAction(book)) { pull(book) }
                                .shelfRow()
                        }
                    } else {
                        let spines = shelved.map(Self.spine(for:))
                        // Keyed by a type of their own: shelves numbered 0, 11, … would otherwise share
                        // ids with the cassettes' Book ids below, and the lazy stack then puts a shelf
                        // in a cassette's place, leaving a gap with books drawn in it.
                        ForEach(Self.fill(spines, width: shelfWidth), id: \.range.shelfID) { shelf in
                            HStack(alignment: .bottom, spacing: Self.spineGap) {
                                ForEach(shelf.range, id: \.self) { index in
                                    spine(shelf.spines[index - shelf.range.lowerBound], of: shelved[index], shelving)
                                }
                            }
                            .shelfRow(minHeight: Spine.heights.upperBound + 14)
                        }
                    }
                }
                if !racked.isEmpty {
                    if headed { headingShelf("Audiobooks") }
                    if usesRows {
                        ForEach(racked) { book in
                            BookRow(book: book, isAudiobook: true, throughBook: shelving.throughBook(book), library: library)
                                .shelved(open: playAction(book)) { pull(book) }
                                .shelfRow()
                        }
                    } else {
                        let columns = max(1, Int((shelfWidth + Self.caseGap) / (Self.caseMinWidth + Self.caseGap)))
                        let caseWidth = (shelfWidth - Self.caseGap * CGFloat(columns - 1)) / CGFloat(columns)
                        ForEach(Self.rows(of: racked, columns: columns), id: \.id) { row in
                            HStack(alignment: .bottom, spacing: Self.caseGap) {
                                ForEach(row.books) { book in
                                    cassette(book, shelving)
                                        .frame(width: max(caseWidth, 1))
                                }
                            }
                            .shelfRow()
                        }
                    }
                }
            }
            .padding(.bottom, 24)
            .environment(coverColors)
        }
        .scrollDismissesKeyboard(.immediately)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
        .background { CanvasBackground() }
        .toolbarBackground(palette.canvas, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(palette.scheme, for: .navigationBar)
        .alert("Couldn't download", isPresented: Binding { downloadProblem != nil } set: { if !$0 { downloadProblem = nil } }) {
            Button("OK") {}
        } message: {
            Text(downloadProblem ?? "")
        }
        // Over the shelves and not in a sheet, so a reader can open straight from the card.
        .overlay {
            if let pulled {
                CatalogCard(
                    book: pulled, library: library,
                    throughBook: pulled.throughBook(including: model.recordedPositions),
                    openable: pulled.readableFiles + Self.openable(pulled, among: [.audiobook]),
                    downloadProblem: $downloadProblem,
                    open: { file in
                        self.pulled = nil
                        Task { await open(file, of: pulled) }
                    },
                    putBack: { self.pulled = nil }
                )
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: pulled?.id)
        // The card covers the shelves, so their bars would only sit on top of it.
        .toolbarVisibility(pulled == nil ? .automatic : .hidden, for: .navigationBar, .bottomBar)
        // The heading shows the name; the title stays for the sidebar's back button and VoiceOver.
        .navigationTitle(navigation.name(of: scope))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(removing: .title)
        .fullScreenCover(item: $reading) { open in
            switch open.reader {
            case let .epub(reader): EPUBReaderView(title: open.title, model: reader)
            case let .pdf(reader): PDFReaderView(title: open.title, model: reader)
            }
        }
        .refreshable { await refresh() }
        .task(id: canSync) {
            if !hasLoaded { await showCached() }
            await refresh()
        }
        .task(id: query) {
            guard hasLoaded else { return }
            await showCached()
        }
    }

    /// The scope's name, one search field and the format filter, scrolling with the shelves.
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(navigation.name(of: scope))
                .serifTitle(34, relativeTo: .largeTitle)
                .foregroundStyle(palette.text)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            SearchField(text: $search)
            Segments(selection: $kind, choices: BookKind.allCases.map { (name: $0.name, value: $0) })
        }
    }

    /// Where the Books end and the Audiobooks begin. The objects say which is which, so the
    /// heading is only there for VoiceOver's rotor.
    private func headingShelf(_ title: String) -> some View {
        Color.clear
            .frame(maxWidth: .infinity, minHeight: 1, maxHeight: 1)
            .accessibilityElement()
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private var emptyState: some View {
        if !search.trimmingCharacters(in: .whitespaces).isEmpty {
            // The query and filters stay above, with a way out.
            VStack(spacing: 12) {
                ContentUnavailableView.search(text: search)
                Button("Clear Search") { search = "" }
                    .buttonStyle(OutlinedActionStyle(fillsWidth: false))
            }
        } else if scope != .everything || kind != .all {
            ContentUnavailableView(kind == .audiobooks ? "No audiobooks here" : kind == .ebooks ? "No Books here" : "Nothing here", systemImage: "books.vertical")
        } else if !canSync {
            // Nothing cached and no Server to ask, which isn't the same as an empty library.
            ContentUnavailableView(
                "Library not loaded yet", systemImage: "wifi.slash",
                description: Text("Your Books show up here once Dogear can reach your Server.")
            )
        } else {
            ContentUnavailableView("No Books yet", systemImage: "books.vertical", description: Text("Books you add in Grimmory show up here."))
        }
    }

    /// Browsing always reads the cache, so it behaves the same offline.
    private func showCached() async {
        navigation = await library.navigation()
        // A library or shelf removed on the Server can't stay selected.
        if !navigation.contains(scope) { scope = .everything }
        books = await library.books(in: scope, matching: search, showing: kind)
    }

    /// Only on the whole library, where they're a way back in rather than part of a search.
    private var showsContinueRows: Bool {
        scope == .everything && search.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The Book files the reader was last in, most recent first: one card in view, the rest a
    /// swipe away, or stacked at accessibility text sizes.
    private func continueShelf(_ entries: [ContinueEntry]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if usesRows {
                VStack(spacing: 10) {
                    ForEach(entries) { entry in continueButton(entry) }
                }
                .padding(.horizontal, Self.inset)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .bottom, spacing: 12) {
                        ForEach(entries) { entry in
                            continueButton(entry)
                                .containerRelativeFrame(.horizontal)
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, Self.inset, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollIndicators(.hidden)
                // A scroll view draws into the side safe areas, so beside iPhone Duo's vertical
                // bar the next card showed past the shelf's end. Cut it off at the shelf's sides,
                // leaving room above and below for the cards' shadows and press lift.
                .mask { Rectangle().padding(.vertical, -40) }
            }
        }
        .padding(.top, 18)
        .shelfRow(insetContent: false)
    }

    private func continueButton(_ entry: ContinueEntry) -> some View {
        Button {
            Task { await open(entry.file, of: entry.book) }
        } label: {
            ContinueCard(entry: entry, heading: ContinueRows.heading(showing: kind), library: library)
        }
        .buttonStyle(LiftsWhenPressed())
    }

    /// One format opens; two or none shows the card, to pick or to see why not.
    private func readAction(_ book: Book) -> (() -> Void)? {
        let files = book.readableFiles
        guard files.count == 1 else { return nil }
        return { Task { await open(files[0], of: book) } }
    }

    private func playAction(_ book: Book) -> (() -> Void)? {
        guard let file = Self.openable(book, among: [.audiobook]).first else { return nil }
        return { Task { await open(file, of: book) } }
    }

    private func spine(_ spine: Spine, of book: Book, _ shelving: ShelvingLookup) -> some View {
        BookSpine(
            book: book, spine: spine, throughBook: shelving.throughBook(book),
            download: shelving.download(of: book.files.filter { $0.format != .audiobook }),
            library: library
        )
        // Reaching into the gap beside it, so a tap between two spines still lands on one.
        .shelved(open: readAction(book), reach: Self.spineGap / 2) { pull(book) }
    }

    private func cassette(_ book: Book, _ shelving: ShelvingLookup) -> some View {
        CassetteCase(
            book: book, throughBook: shelving.throughBook(book),
            download: shelving.download(of: book.files.filter { $0.format == .audiobook })
        )
        .shelved(open: playAction(book)) { pull(book) }
    }

    /// A spine wide enough that its longest word fits across it at the standard type size, up
    /// to the widest a spine gets.
    private static func spine(for book: Book) -> Spine {
        var spine = Spine(book: book)
        let needed = Double(SpineType.neededThickness(for: spine.title))
        spine.thickness = min(max(spine.thickness, needed), Spine.thicknesses.upperBound)
        return spine
    }

    /// Spines shared out over shelves of `width`, then each shelf's spines stretched or squeezed
    /// in proportion to span it, so every shelf is full and thick Books stay thicker than thin
    /// ones. A shelf with too few Books to span it without looking bloated keeps a gap.
    private static func fill(_ spines: [Spine], width: CGFloat) -> [FilledShelf] {
        guard width > 0 else { return [] }
        let ranges = Shelves.balanced(thicknesses: spines.map(\.thickness), shelfWidth: width, spacing: spineGap)
        return ranges.map { range in
            var shelf = Array(spines[range])
            let natural = shelf.map(\.thickness).reduce(0, +)
            let room = width - spineGap * Double(shelf.count - 1)
            let scale = min(max(room / max(natural, 1), Shelves.stretch.lowerBound), Shelves.stretch.upperBound)
            for index in shelf.indices { shelf[index].thickness = (shelf[index].thickness * scale).rounded(.down) }
            return FilledShelf(range: range, spines: shelf)
        }
    }

    private struct FilledShelf {
        let range: Range<Int>
        let spines: [Spine]
    }

    /// Cases in rows of `columns`, the last row left-aligned.
    private static func rows(of books: [Book], columns: Int) -> [CaseRow] {
        stride(from: 0, to: books.count, by: columns).map { start in
            let row = Array(books[start ..< min(start + columns, books.count)])
            return CaseRow(id: CaseRowID(firstBook: row[0].id, columns: columns), books: row)
        }
    }

    private struct CaseRow {
        let id: CaseRowID
        let books: [Book]
    }

    /// Takes the Book off the shelf to show its catalog card.
    private func pull(_ book: Book) {
        pulled = book
        // Found the card, so the tip pointing to it has done its job.
        CatalogCardTip().invalidate(reason: .actionPerformed)
    }

    /// The Book files a tap can open, one per format in `formats`' order.
    private static func openable(_ book: Book, among formats: [BookFile.Format]) -> [BookFile] {
        let supported = book.files.filter(\.isSupported)
        return formats.compactMap { format in supported.first { $0.format == format } }
    }

    private func open(_ file: BookFile, of book: Book) async {
        // The player lives above the library, so it can play on while closed.
        if file.format == .audiobook {
            await model.play(book)
            return
        }
        let reader: OpenBookFile.Reader? = switch file.format {
        case .epub, .mobi, .azw3, .fb2: await model.epubReader(for: book, file: file).map(OpenBookFile.Reader.epub)
        case .pdf: await model.pdfReader(for: book, file: file).map(OpenBookFile.Reader.pdf)
        default: nil
        }
        guard let reader else { return }
        reading = OpenBookFile(title: book.title, reader: reader)
    }

    private struct OpenBookFile: Identifiable {
        enum Reader {
            case epub(EPUBReaderModel)
            case pdf(PDFReaderModel)
        }

        let id = UUID()
        let title: String
        let reader: Reader
    }

    private func refresh() async {
        do {
            _ = try await library.refresh()
            problem = nil
        } catch .needsSignIn, .signedOut, .unreachable, .serverChanged {
            // A banner already explains these; keep showing the cached Books.
            problem = nil
        } catch {
            problem = error
        }
        await showCached()
        await model.showContinueRows()
        hasLoaded = true
    }

    private struct Query: Hashable {
        var scope: BookScope
        var search: String
        var kind: BookKind
    }
}

/// Positions and Downloads by Book file, built once per update of the shelves. A large library
/// otherwise searched every Position and Download for every spine on each progress tick.
/// Which shelf of ebooks this is, by its first spine. Not a plain `Int`, so it never equals a
/// Book's id in the same lazy stack.
private struct ShelfID: Hashable {
    let firstSpine: Int
}

private extension Range<Int> {
    var shelfID: ShelfID { ShelfID(firstSpine: lowerBound) }
}

private struct ShelvingLookup {
    private let positions: [Int: [Position]]
    private let downloads: [Int: Download.State]

    init(positions: [Position], downloads: DownloadList) {
        self.positions = Dictionary(grouping: positions, by: \.bookFileID)
        // The first for each Book file, as `DownloadList.download(bookFileID:)` finds.
        self.downloads = Dictionary(downloads.downloads.map { ($0.bookFileID, $0.state) }, uniquingKeysWith: { first, _ in first })
    }

    func throughBook(_ book: Book) -> Double? {
        book.throughBook(including: book.files.flatMap { positions[$0.id] ?? [] })
    }

    func download(of files: [BookFile]) -> ShelfDownload {
        ShelfDownload(files.compactMap { downloads[$0.id] })
    }
}

/// The card behind a press and hold is where Downloads are, and nothing on a spine says so.
private struct CatalogCardTip: Tip {
    var title: Text { Text("Press and hold a Book") }
    var message: Text? { Text("Its catalog card shows every format, and downloads it for reading offline.") }
    var image: Image? { Image(systemName: "hand.tap") }
}

/// Which row of cassette cases this is, by its first Book. Not a plain `Int`, so it never
/// equals a shelf's or a Book's id in the same lazy stack.
private struct CaseRowID: Hashable {
    let firstBook: Int
    let columns: Int
}

private extension View {
    /// One stretch of the bookcase: its content on the backing, standing on a ledge, the whole
    /// width of the column so all the shelves read as one piece of furniture.
    func shelfRow(minHeight: CGFloat = 0, insetContent: Bool = true) -> some View {
        modifier(ShelfRow(minHeight: minHeight, insetContent: insetContent))
    }
}

private struct ShelfRow: ViewModifier {
    let minHeight: CGFloat
    let insetContent: Bool

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            content
                .padding(.horizontal, insetContent ? LibraryView.inset : 0)
                .padding(.top, insetContent ? 14 : 0)
                .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .bottomLeading)
                .padding(.bottom, 0)
                .background { ShelfBacking() }
            ShelfLedge()
        }
    }
}

/// The Library's one search field, on paper.
private struct SearchField: View {
    @Binding var text: String

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(palette.inkSecondary)
                .accessibilityHidden(true)
            TextField(text: $text, prompt: Text("Search your library").foregroundStyle(palette.inkSecondary)) {
                Text("Search your library")
            }
            .foregroundStyle(palette.ink)
            .submitLabel(.search)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            if !text.isEmpty {
                Button("Clear Search", systemImage: "xmark.circle.fill") { text = "" }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(palette.inkSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
        }
        .font(.body)
        .padding(.leading, 12)
        .padding(.trailing, text.isEmpty ? 12 : 0)
        .frame(minHeight: 44)
        .background(palette.raised, in: .rect(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(palette.boundary, lineWidth: 1) }
        .environment(\.colorScheme, .light)
        .tint(palette.paperAction)
    }
}

/// A Book file in the Continue shelf: its cover or cassette, what it is and how far in, and a
/// way back in. The whole card is one button.
private struct ContinueCard: View {
    let entry: ContinueEntry
    /// "Continue", "Continue Reading" or "Continue Listening".
    let heading: String
    let library: Library

    @Environment(CoverColors.self) private var coverColors
    @Environment(\.palette) private var palette
    @ScaledMetric(relativeTo: .body) private var thumbnailWidth: CGFloat = 104

    private var isAudiobook: Bool { entry.file.format == .audiobook }

    private var cover: Cover? {
        isAudiobook ? entry.book.audiobookCover ?? entry.book.cover : entry.book.ebookCover ?? entry.book.cover
    }

    private var throughBook: Double? { entry.position?.location.throughBook }

    private var percent: String? {
        throughBook.map { $0.formatted(.percent.precision(.fractionLength(0))) }
    }

    var body: some View {
        // The cover beside a paper card, centred on it: a square audiobook cover is much shorter
        // than a book's, and stood on the ledge it sat low beside the card.
        HStack(alignment: .center, spacing: 12) {
            CoverImage(cover: cover, title: entry.book.title, library: library)
                .frame(width: min(thumbnailWidth, 104), height: 150)
                .shadow(color: .black.opacity(0.35), radius: 4, x: 3, y: 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(heading.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(1.4)
                    .foregroundStyle(palette.accent)
                Text(entry.book.title)
                    .serifTitle(20, relativeTo: .title3)
                    .foregroundStyle(palette.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                if let author = entry.book.authors.first {
                    Text(author)
                        .font(.system(.subheadline, design: .serif))
                        .foregroundStyle(palette.inkSecondary)
                        .lineLimit(1)
                }
                if let throughBook {
                    ProgressBar(value: throughBook, track: palette.inkSecondary.opacity(0.25))
                        .padding(.top, 6)
                }
                HStack(spacing: 6) {
                    Text([percent, isAudiobook ? "Audiobook" : entry.file.format.name].compactMap(\.self).joined(separator: "  ·  "))
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(palette.inkSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: isAudiobook ? "play.circle.fill" : "chevron.right")
                        .font(isAudiobook ? .title2 : .body.weight(.semibold))
                        .foregroundStyle(isAudiobook ? palette.accent : palette.ink)
                        .accessibilityHidden(true)
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .paperCard(radius: 8)
        }
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: cover) { await coverColors.load(cover, from: library) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityHint(isAudiobook ? "Resumes listening" : "Resumes reading")
    }

    private var spoken: String {
        var parts = ["Continue", entry.book.title]
        if let author = entry.book.authors.first { parts.append(author) }
        parts.append(isAudiobook ? "Audiobook" : entry.file.format.name)
        if let percent { parts.append("\(percent) \(isAudiobook ? "played" : "read")") }
        return parts.joined(separator: ", ")
    }
}

/// A thin progress bar in the theme's accent.
struct ProgressBar: View {
    let value: Double
    let track: Color

    @Environment(\.palette) private var palette

    var body: some View {
        Capsule()
            .fill(track)
            .frame(height: 4)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule().fill(palette.accent).frame(width: proxy.size.width * min(max(value, 0), 1))
                }
            }
            .accessibilityHidden(true)
    }
}

/// A Book as a full-width row at accessibility text sizes: its cover, then its title, author and
/// formats wrapping as far as they need.
private struct BookRow: View {
    let book: Book
    let isAudiobook: Bool
    let throughBook: Double?
    let library: Library

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CoverImage(cover: isAudiobook ? book.audiobookCover ?? book.cover : book.ebookCover ?? book.cover, title: book.title, library: library)
                .frame(width: 64)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .serifTitle(20, relativeTo: .title3)
                if !book.authors.isEmpty {
                    Text(book.authors.formatted(.list(type: .and)))
                        .font(.body)
                        .foregroundStyle(palette.inkSecondary)
                }
                Text(BookFormats.labels(for: book.files).joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(palette.inkSecondary)
                if let throughBook {
                    Text("\(throughBook.formatted(.percent.precision(.fractionLength(0)))) \(isAudiobook ? "played" : "read")")
                        .font(.footnote)
                        .foregroundStyle(palette.inkSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .paperCard(radius: 12)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
    }
}

private extension View {
    /// A Book on a shelf or in the rack: a tap opens it, a long press pulls it out to show its
    /// catalog card. Without `open`, a tap pulls it out too. `reach` widens where a tap lands.
    func shelved(open: (() -> Void)?, reach: CGFloat = 0, pull: @escaping () -> Void) -> some View {
        modifier(Shelved(open: open, reach: reach, pull: pull))
    }
}

private struct Shelved: ViewModifier {
    let open: (() -> Void)?
    let reach: CGFloat
    let pull: () -> Void

    @State private var isPressed = false

    func body(content: Content) -> some View {
        content
            .modifier(Lifted(isPressed: isPressed))
            .padding(.horizontal, reach)
            .contentShape(.rect)
            .onTapGesture(perform: open ?? pull)
            .onLongPressGesture(perform: pull, onPressingChanged: { isPressed = $0 })
            .padding(.horizontal, -reach)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "Show Details", pull)
    }
}

/// A Book raised a little off the shelf while a finger is on it.
private struct Lifted: ViewModifier {
    let isPressed: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .offset(y: isPressed && !reduceMotion ? -4 : 0)
            .brightness(isPressed ? 0.08 : 0)
            .animation(.snappy(duration: 0.15), value: isPressed)
    }
}

private struct LiftsWhenPressed: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.modifier(Lifted(isPressed: configuration.isPressed))
    }
}
