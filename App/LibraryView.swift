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
    @State private var downloadProblem: String?
    @State private var coverColors = CoverColors()
    /// The scroll view's width, which decides how many spines a shelf holds.
    @State private var width: CGFloat = 0
    @Environment(AppModel.self) private var model

    private static let margin: CGFloat = 14
    private static let caseSide: CGFloat = 12
    private static let spineGap: CGFloat = 2
    private static let rack = LinearGradient(
        stops: [
            .init(color: Color(hex: 0x141416), location: 0),
            .init(color: Color(hex: 0x2A2A2E), location: 0.06),
            .init(color: Color(hex: 0x2A2A2E), location: 0.94),
            .init(color: Color(hex: 0x141416), location: 1),
        ],
        startPoint: .leading, endPoint: .trailing
    )

    private var query: Query { Query(scope: scope, search: search, kind: kind) }

    /// Books with an ebook file stand on the shelves; an unsupported one still has its place.
    private var ebooks: [Book] {
        kind == .audiobooks ? [] : books.filter { $0.files.contains { $0.format != .audiobook } }
    }

    /// Books with an audiobook file lie in the cassette rack. A Book with both is in both.
    private var audiobooks: [Book] {
        kind == .ebooks ? [] : books.filter { $0.files.contains { $0.format == .audiobook } }
    }

    var body: some View {
        let shelved = ebooks
        let racked = audiobooks
        let spines = shelved.map(Spine.init)
        // Looked up per Book file below, so each spine doesn't search every Position and Download.
        let shelving = ShelvingLookup(positions: model.recordedPositions, downloads: model.downloadList)
        // Inside the page margin and the bookcase's own sides.
        let shelves = width > 0
            ? Shelves.fill(thicknesses: spines.map(\.thickness), shelfWidth: width - 2 * (Self.margin + Self.caseSide), spacing: Self.spineGap)
            : []
        ScrollView {
            // Every shelf and cassette is its own lazy row, so a large library only builds what's on screen.
            LazyVStack(spacing: 0) {
                ClothBoard(title: navigation.name(of: scope), subtitle: books.count == 1 ? "1 Book" : "\(books.count) Books")
                    .padding(.bottom, 16)
                LeatherTabs {
                    ForEach(BookKind.allCases, id: \.self) { kind in
                        Button(kind.name) { self.kind = kind }
                            .buttonStyle(LeatherTabStyle(isOn: self.kind == kind))
                            .accessibilityAddTraits(self.kind == kind ? .isSelected : [])
                    }
                }
                .padding(.bottom, 18)
                if let problem, let message = problem.errorDescription {
                    PaperTag {
                        Label(message, systemImage: "wifi.exclamationmark")
                            .font(.footnote)
                            .foregroundStyle(Theme.inkSoft)
                    }
                    .padding(.bottom, 18)
                }
                if showsContinueRows {
                    if kind != .audiobooks, !model.continueRows.reading.isEmpty {
                        continueShelf("Continue Reading", model.continueRows.reading, height: 176)
                    }
                    if kind != .ebooks, !model.continueRows.listening.isEmpty {
                        continueShelf("Continue Listening", model.continueRows.listening, height: CassetteFace.size.height + 34)
                    }
                }
                if !shelved.isEmpty || !racked.isEmpty {
                    TipView(CatalogCardTip())
                        .tipBackground(Theme.paper)
                        .tint(Theme.ribbon)
                        // Paper is light whatever the device's appearance.
                        .environment(\.colorScheme, .light)
                        .padding(.bottom, 18)
                }
                if !shelved.isEmpty {
                    ShelfLabel("Ebooks")
                        .padding(.bottom, 10)
                    ForEach(shelves, id: \.lowerBound) { shelf in
                        BookShelf {
                            ForEach(shelf, id: \.self) { index in
                                spine(spines[index], of: shelved[index], shelving)
                            }
                        }
                    }
                    .padding(.bottom, 14)
                }
                if !racked.isEmpty {
                    ShelfLabel("Audiobooks")
                        .padding(.top, 8)
                        .padding(.bottom, 10)
                    Self.rack
                        .frame(height: 10)
                        .clipShape(.rect(topLeadingRadius: 8, topTrailingRadius: 8))
                    ForEach(racked) { book in
                        cassette(book, shelving)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 4)
                            .background(Self.rack)
                    }
                    Self.rack
                        .frame(height: 10)
                        .clipShape(.rect(bottomLeadingRadius: 8, bottomTrailingRadius: 8))
                        .shadow(color: .black.opacity(0.6), radius: 8, y: 8)
                }
            }
            .padding(.horizontal, Self.margin)
            .padding(.top, 8)
            .padding(.bottom, 30)
            .environment(coverColors)
            // The bookcase is dark wood whatever the device's appearance. Set here and not on the
            // whole view, so the readers it presents keep following the device.
            .environment(\.colorScheme, .dark)
            .tint(Theme.accent)
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
        .background { FeltBackground() }
        .toolbarColorScheme(.dark, for: .navigationBar)
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
        // The nameplate shows the name; the title stays for the sidebar's back button and VoiceOver.
        .navigationTitle(navigation.name(of: scope))
        // Inline, or the large title would repeat the nameplate above it.
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(removing: .title)
        // In the bar, so it leaves with the bar when a Book is pulled and never floats over the rack.
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Title or author")
        .overlay {
            Group {
                if hasLoaded, books.isEmpty, problem == nil {
                    emptyState
                } else if !hasLoaded, books.isEmpty {
                    ProgressView()
                }
            }
            .environment(\.colorScheme, .dark)
            .tint(Theme.accent)
        }
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

    @ViewBuilder private var emptyState: some View {
        if !search.trimmingCharacters(in: .whitespaces).isEmpty {
            ContentUnavailableView.search(text: search)
        } else if scope != .everything || kind != .all {
            ContentUnavailableView("No Books here", systemImage: "books.vertical")
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

    /// The Book files the reader was last in, face out on a shelf of their own.
    /// `height` fits what stands on it: covers are taller than cassettes.
    private func continueShelf(_ title: String, _ entries: [ContinueEntry], height: CGFloat) -> some View {
        VStack(spacing: 10) {
            ShelfLabel(title)
            BookShelf(height: height) {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .bottom, spacing: 16) {
                        ForEach(entries) { entry in
                            Button {
                                Task { await open(entry.file, of: entry.book) }
                            } label: {
                                ContinueCard(entry: entry, library: library)
                            }
                            .buttonStyle(LiftsWhenPressed())
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .modifier(FadesWhereMoreToCome())
            }
        }
        .padding(.bottom, 18)
    }

    private func spine(_ spine: Spine, of book: Book, _ shelving: ShelvingLookup) -> some View {
        let files = book.readableFiles
        // One format opens; two or none shows the card, to pick or to see why not.
        var read: (() -> Void)?
        if files.count == 1 { read = { Task { await open(files[0], of: book) } } }
        return BookSpine(
            book: book, spine: spine, throughBook: shelving.throughBook(book),
            download: shelving.download(of: book.files.filter { $0.format != .audiobook }),
            library: library
        )
        // Reaching into the gap beside it, so a tap between two thin spines still lands on one.
        .shelved(open: read, reach: Self.spineGap / 2) { pull(book) }
    }

    private func cassette(_ book: Book, _ shelving: ShelvingLookup) -> some View {
        var play: (() -> Void)?
        if let file = Self.openable(book, among: [.audiobook]).first { play = { Task { await open(file, of: book) } } }
        return CassetteCase(
            book: book, throughBook: shelving.throughBook(book),
            download: shelving.download(of: book.files.filter { $0.format == .audiobook }),
            library: library
        )
        .shelved(open: play) { pull(book) }
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

/// A row of Books on the back panel of the bookcase, standing on a ledge.
private struct BookShelf<Content: View>: View {
    /// Room for the tallest spine and a ribbon above it.
    var height: CGFloat = Spine.heights.upperBound + 22
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 2) { content }
                .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .bottomLeading)
                .padding(.horizontal, 12)
                .background(Theme.backPanel)
            ShelfLedge()
        }
    }
}

/// A Book file in a continue shelf: an ebook's cover with a bookmark, or an audiobook's cassette.
/// Either shows how far in the reader is.
private struct ContinueCard: View {
    let entry: ContinueEntry
    let library: Library

    @Environment(CoverColors.self) private var coverColors

    private var isAudiobook: Bool { entry.file.format == .audiobook }

    private var cover: Cover? {
        isAudiobook ? entry.book.audiobookCover ?? entry.book.cover : entry.book.ebookCover ?? entry.book.cover
    }

    private var throughBook: Double? { entry.position?.location.throughBook }

    var body: some View {
        Group {
            if isAudiobook {
                CassetteFace(
                    title: Spine.title(for: entry.book.title), throughBook: throughBook ?? 0,
                    stripe: Color(coverColors.color(of: cover) ?? Spine(book: entry.book).fallbackColor)
                )
                .padding(.bottom, 10)
                .task(id: cover) { await coverColors.load(cover, from: library) }
            } else {
                CoverImage(cover: cover, library: library)
                    .frame(width: 96, height: 144, alignment: .bottom)
                    .shadow(color: .black.opacity(0.6), radius: 6, x: 4, y: 6)
                    .overlay(alignment: .topTrailing) {
                        if let throughBook {
                            Text(throughBook.formatted(.percent.precision(.fractionLength(0))))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Theme.ink)
                                .padding(.horizontal, 4)
                                .padding(.top, 2)
                                .padding(.bottom, 7)
                                .background(Theme.paper, in: Ribbon())
                                .offset(x: -10, y: -12)
                        }
                    }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var spoken: String {
        guard let throughBook else { return entry.book.title }
        return "\(entry.book.title), \(throughBook.formatted(.percent.precision(.fractionLength(0))))"
    }
}

struct CoverImage: View {
    let cover: Cover?
    let library: Library

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(.rect(cornerRadius: 4))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.fill.tertiary)
                    .overlay { Image(systemName: "book.closed").foregroundStyle(.secondary) }
            }
        }
        .task(id: cover) {
            guard let cover, let data = await library.image(for: cover) else { return }
            image = UIImage(data: data)
        }
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

/// Fades out the end of a sideways shelf while more stands beyond it, so what doesn't fit reads
/// as more to come and not as cut off. With everything in view nothing fades.
private struct FadesWhereMoreToCome: ViewModifier {
    @State private var hasMore = false

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.x + geometry.containerSize.width < geometry.contentSize.width - 1
            } action: { _, hasMore in
                self.hasMore = hasMore
            }
            .mask {
                LinearGradient(
                    stops: [.init(color: .black, location: 0.92), .init(color: hasMore ? .clear : .black, location: 1)],
                    startPoint: .leading, endPoint: .trailing
                )
            }
    }
}
