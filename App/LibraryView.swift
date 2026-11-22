import DogearCore
import SwiftUI

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
    /// A Book with several formats, waiting for the reader to pick one.
    @State private var choosingFormat: Book?
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
        // Inside the page margin and the bookcase's own sides.
        let shelves = width > 0
            ? Shelves.fill(thicknesses: spines.map(\.thickness), shelfWidth: width - 2 * (Self.margin + Self.caseSide), spacing: Self.spineGap)
            : []
        ScrollView {
            // Every shelf and cassette is its own lazy row, so a large library only builds what's on screen.
            LazyVStack(spacing: 0) {
                Nameplate(title: navigation.name(of: scope), subtitle: books.count == 1 ? "1 Book" : "\(books.count) Books")
                    .padding(.bottom, 16)
                HStack(spacing: 8) {
                    ForEach(BookKind.allCases, id: \.self) { kind in
                        Button(kind.name) { self.kind = kind }
                            .buttonStyle(DrawerButtonStyle(isOn: self.kind == kind))
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
                        continueShelf("Continue Reading", model.continueRows.reading)
                    }
                    if kind != .ebooks, !model.continueRows.listening.isEmpty {
                        continueShelf("Continue Listening", model.continueRows.listening)
                    }
                }
                if !shelved.isEmpty {
                    ShelfLabel("Ebooks")
                        .padding(.bottom, 10)
                    ForEach(shelves, id: \.lowerBound) { shelf in
                        BookShelf {
                            ForEach(shelf, id: \.self) { index in
                                spine(spines[index], of: shelved[index])
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
                        cassette(book)
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
            .tint(Theme.gilt)
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
        .background { WoodBackground() }
        .toolbarColorScheme(.dark, for: .navigationBar)
        .alert("Couldn't download", isPresented: Binding { downloadProblem != nil } set: { if !$0 { downloadProblem = nil } }) {
            Button("OK") {}
        } message: {
            Text(downloadProblem ?? "")
        }
        .confirmationDialog(
            "Open",
            isPresented: Binding { choosingFormat != nil } set: { if !$0 { choosingFormat = nil } },
            presenting: choosingFormat
        ) { book in
            ForEach(Self.openable(book, among: Self.ebookFormats)) { file in
                Button(file.format.name) { Task { await open(file, of: book) } }
            }
        }
        // The nameplate shows the name; the title stays for the sidebar's back button and VoiceOver.
        .navigationTitle(navigation.name(of: scope))
        .toolbar(removing: .title)
        .searchable(text: $search, prompt: "Title or author")
        .overlay {
            Group {
                if hasLoaded, books.isEmpty, problem == nil {
                    emptyState
                } else if !hasLoaded, books.isEmpty {
                    ProgressView()
                }
            }
            .environment(\.colorScheme, .dark)
            .tint(Theme.gilt)
        }
        .fullScreenCover(item: $reading) { open in
            switch open.reader {
            case let .epub(reader): EPUBReaderView(title: open.title, model: reader)
            case let .pdf(reader): PDFReaderView(title: open.title, model: reader)
            case let .audiobook(player, cover): AudiobookPlayerView(model: player, cover: cover, library: library)
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
    private func continueShelf(_ title: String, _ entries: [ContinueEntry]) -> some View {
        VStack(spacing: 10) {
            ShelfLabel(title)
            BookShelf(height: 176) {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .bottom, spacing: 16) {
                        ForEach(entries) { entry in
                            Button {
                                Task { await open(entry.file, of: entry.book) }
                            } label: {
                                ContinueCard(entry: entry, library: library)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(.bottom, 18)
    }

    private func spine(_ spine: Spine, of book: Book) -> some View {
        let files = Self.openable(book, among: Self.ebookFormats)
        return Button {
            guard let file = files.first else { return }
            if files.count > 1 {
                choosingFormat = book
            } else {
                Task { await open(file, of: book) }
            }
        } label: {
            BookSpine(
                book: book, spine: spine, throughBook: book.throughBook(including: model.recordedPositions),
                download: ShelfDownload(of: book.files.filter { $0.format != .audiobook }, in: model.downloadList),
                library: library
            )
        }
        .buttonStyle(.plain)
        .contextMenu { DownloadMenu(book: book, problem: $downloadProblem) }
    }

    private func cassette(_ book: Book) -> some View {
        let files = Self.openable(book, among: [.audiobook])
        return Button {
            guard let file = files.first else { return }
            Task { await open(file, of: book) }
        } label: {
            CassetteCase(
                book: book, throughBook: book.throughBook(including: model.recordedPositions),
                download: ShelfDownload(of: book.files.filter { $0.format == .audiobook }, in: model.downloadList),
                library: library
            )
        }
        .buttonStyle(.plain)
        .contextMenu { DownloadMenu(book: book, problem: $downloadProblem) }
    }

    /// EPUB first, since it reflows. With both, the reader picks.
    private static let ebookFormats: [BookFile.Format] = [.epub, .pdf]

    /// The Book files a tap can open, one per format in `formats`' order.
    private static func openable(_ book: Book, among formats: [BookFile.Format]) -> [BookFile] {
        let supported = book.files.filter(\.isSupported)
        return formats.compactMap { format in supported.first { $0.format == format } }
    }

    private func open(_ file: BookFile, of book: Book) async {
        let reader: OpenBookFile.Reader? = switch file.format {
        case .epub: await model.epubReader(for: book, file: file).map(OpenBookFile.Reader.epub)
        case .pdf: await model.pdfReader(for: book, file: file).map(OpenBookFile.Reader.pdf)
        case .audiobook: await model.audiobookPlayer(for: book).map { .audiobook($0, cover: book.audiobookCover ?? book.cover) }
        default: nil
        }
        guard let reader else { return }
        reading = OpenBookFile(title: book.title, reader: reader)
    }

    private struct OpenBookFile: Identifiable {
        enum Reader {
            case epub(EPUBReaderModel)
            case pdf(PDFReaderModel)
            case audiobook(AudiobookPlayerModel, cover: Cover?)
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
                                .font(.custom("Noteworthy-Bold", fixedSize: 11))
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

private struct CoverImage: View {
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
