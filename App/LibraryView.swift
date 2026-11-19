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
    @Environment(AppModel.self) private var model

    private var query: Query { Query(scope: scope, search: search, kind: kind) }

    var body: some View {
        List {
            if let problem, let message = problem.errorDescription {
                Label(message, systemImage: "wifi.exclamationmark")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Picker("Show", selection: $kind) {
                ForEach(BookKind.allCases, id: \.self) { kind in
                    Text(kind.name).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)
            if showsContinueRows {
                if kind != .audiobooks, !model.continueRows.reading.isEmpty {
                    continueRow("Continue Reading", model.continueRows.reading)
                }
                if kind != .ebooks, !model.continueRows.listening.isEmpty {
                    continueRow("Continue Listening", model.continueRows.listening)
                }
            }
            ForEach(books) { book in
                Group {
                    let files = Self.openable(book)
                    if let file = files.first {
                        Button {
                            if files.count > 1 {
                                choosingFormat = book
                            } else {
                                Task { await open(file, of: book) }
                            }
                        } label: {
                            BookRow(book: book, library: library, throughBook: book.throughBook(including: model.recordedPositions))
                        }
                        .foregroundStyle(.primary)
                    } else {
                        BookRow(book: book, library: library, throughBook: book.throughBook(including: model.recordedPositions))
                    }
                }
                .contextMenu { DownloadMenu(book: book, problem: $downloadProblem) }
            }
        }
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
            ForEach(Self.openable(book)) { file in
                Button(file.format.name) { Task { await open(file, of: book) } }
            }
        }
        .navigationTitle(navigation.name(of: scope))
        .searchable(text: $search, prompt: "Title or author")
        .overlay {
            if hasLoaded, books.isEmpty, problem == nil {
                emptyState
            } else if !hasLoaded, books.isEmpty {
                ProgressView()
            }
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

    private func continueRow(_ title: String, _ entries: [ContinueEntry]) -> some View {
        Section(title) {
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 16) {
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
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
    }

    /// The Book files a tap can open, one per format: EPUB first, since it reflows, then PDF,
    /// then audiobook. With more than one, the reader picks.
    private static func openable(_ book: Book) -> [BookFile] {
        let supported = book.files.filter(\.isSupported)
        return [BookFile.Format.epub, .pdf, .audiobook].compactMap { format in supported.first { $0.format == format } }
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

struct BookRow: View {
    let book: Book
    let library: Library
    /// nil when the Book was never read.
    let throughBook: Double?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CoverImage(cover: book.cover, library: library)
                .frame(width: 56, height: 84)
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.headline)
                    .lineLimit(2)
                if !book.authors.isEmpty {
                    Text(book.authors.formatted(.list(type: .and)))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    BookFileFormats(files: book.files)
                    DownloadBadge(book: book)
                }
                if let throughBook {
                    Text(throughBook.formatted(.percent.precision(.fractionLength(0))))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A Book file in a continue row: its cover, title and how far in the reader is.
private struct ContinueCard: View {
    let entry: ContinueEntry
    let library: Library

    private var cover: Cover? {
        entry.file.format == .audiobook ? entry.book.audiobookCover ?? entry.book.cover : entry.book.ebookCover ?? entry.book.cover
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            CoverImage(cover: cover, library: library)
                .frame(width: 96, height: 144)
            Text(entry.book.title)
                .font(.caption)
                .lineLimit(2)
            if let throughBook = entry.position?.location.throughBook {
                Text(throughBook.formatted(.percent.precision(.fractionLength(0))))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 96, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Each format once, with formats Dogear can't open marked as such.
private struct BookFileFormats: View {
    let files: [BookFile]

    private var labels: [String] {
        files.reduce(into: []) { labels, file in
            let label = file.isSupported ? file.format.name : "\(file.format.name) (format not supported)"
            if !labels.contains(label) { labels.append(label) }
        }
    }

    var body: some View {
        Text(labels.joined(separator: " · "))
            .font(.caption)
            .foregroundStyle(.secondary)
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
