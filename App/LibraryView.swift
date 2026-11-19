import DogearCore
import SwiftUI

struct LibraryView: View {
    let library: Library
    /// False while the Server refuses the refresh token; signing in again reloads the list.
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
            ForEach(books) { book in
                if let file = Self.openable(book) {
                    Button {
                        Task { await open(file, of: book) }
                    } label: {
                        BookRow(book: book, library: library)
                    }
                    .foregroundStyle(.primary)
                } else {
                    BookRow(book: book, library: library)
                }
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
            switch open.content {
            case let .epub(reader):
                EPUBReaderView(title: open.title, model: reader)
            case let .audiobook(player, cover):
                AudiobookPlayerView(model: player, cover: cover, library: library)
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

    /// The Book file a tap opens: the primary one when Dogear can open it, otherwise the first that it can.
    private static func openable(_ book: Book) -> BookFile? {
        let files = book.files.filter { $0.isSupported && [.epub, .audiobook].contains($0.format) }
        return files.first { $0.id == book.primaryFileID } ?? files.first
    }

    private func open(_ file: BookFile, of book: Book) async {
        switch file.format {
        case .audiobook:
            guard let player = await model.audiobookPlayer(for: book) else { return }
            reading = OpenBookFile(title: book.title, content: .audiobook(player, cover: book.audiobookCover ?? book.cover))
        default:
            guard let reader = await model.epubReader(for: book, file: file) else { return }
            reading = OpenBookFile(title: book.title, content: .epub(reader))
        }
    }

    private struct OpenBookFile: Identifiable {
        enum Content {
            case epub(EPUBReaderModel)
            case audiobook(AudiobookPlayerModel, cover: Cover?)
        }

        let id = UUID()
        let title: String
        let content: Content
    }

    private func refresh() async {
        do {
            _ = try await library.refresh()
            problem = nil
        } catch .needsSignIn, .signedOut {
            // The sign-in banner already explains this; keep showing the cached Books.
            problem = nil
        } catch {
            problem = error
        }
        await showCached()
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
                BookFileFormats(files: book.files)
            }
        }
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
