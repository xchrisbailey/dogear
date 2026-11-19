import DogearCore
import SwiftUI

struct LibraryView: View {
    let library: Library
    /// False while the Server refuses the refresh token; signing in again reloads the list.
    let canSync: Bool

    @State private var books: [Book] = []
    @State private var hasLoaded = false
    @State private var problem: RequestError?
    @State private var reading: OpenBookFile?
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            if let problem, let message = problem.errorDescription {
                Label(message, systemImage: "wifi.exclamationmark")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(books) { book in
                if let epub = book.files.first(where: { $0.format == .epub && $0.isSupported }) {
                    Button {
                        Task { await open(epub, of: book) }
                    } label: {
                        BookRow(book: book, library: library)
                    }
                    .foregroundStyle(.primary)
                } else {
                    BookRow(book: book, library: library)
                }
            }
        }
        .overlay {
            if hasLoaded, books.isEmpty, problem == nil {
                ContentUnavailableView("No Books yet", systemImage: "books.vertical", description: Text("Books you add in Grimmory show up here."))
            } else if !hasLoaded, books.isEmpty {
                ProgressView()
            }
        }
        .fullScreenCover(item: $reading) { open in
            EPUBReaderView(title: open.title, model: open.reader)
        }
        .refreshable { await refresh() }
        .task(id: canSync) {
            if !hasLoaded { books = await library.cachedBooks() }
            await refresh()
        }
    }

    private func open(_ file: BookFile, of book: Book) async {
        guard let reader = await model.epubReader(for: book, file: file) else { return }
        reading = OpenBookFile(title: book.title, reader: reader)
    }

    private struct OpenBookFile: Identifiable {
        let id = UUID()
        let title: String
        let reader: EPUBReaderModel
    }

    private func refresh() async {
        do {
            books = try await library.refresh()
            problem = nil
        } catch .needsSignIn, .signedOut {
            // The sign-in banner already explains this; keep showing the cached Books.
            problem = nil
        } catch {
            problem = error
        }
        hasLoaded = true
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
