import Foundation

/// The signed-in reader's Books: fetched from the Server, kept in a `LibraryStore` for offline use.
public actor Library {
    private let account: Account
    private let cache: LibraryCache

    public init(account: Account, store: LibraryStore) {
        self.account = account
        cache = LibraryCache(modelContainer: store.container)
    }

    /// The Books from the last successful refresh, available without the Server.
    public func cachedBooks() async -> [Book] {
        await cache.books()
    }

    /// Fetches the latest Books and replaces the cached list. On failure the cache is left as it was.
    public func refresh() async throws(RequestError) -> [Book] {
        let books = try await client().books()
        // A failed save only costs the offline copy; the fresh list is still worth showing.
        try? await cache.replaceBooks(with: books)
        return books
    }

    /// The cover image, from the cache when it's there, otherwise fetched and cached. nil when unavailable.
    public func image(for cover: Cover) async -> Data? {
        if let cached = await cache.image(for: cover) { return cached }
        guard let image = await client().image(for: cover) else { return nil }
        try? await cache.store(image, for: cover)
        return image
    }

    /// Drops the cached Books and covers, so the next account or Server starts clean.
    public func forget() async {
        try? await cache.clear()
    }

    private func client() async -> LibraryClient {
        LibraryClient(account: account, server: await account.session?.server)
    }
}

/// The app-API calls behind the Library.
private struct LibraryClient {
    let account: Account
    /// nil when signed out; requests then fail with `.signedOut`.
    let server: URL?

    private struct Page: Decodable {
        struct Summary: Decodable { var id: Int }
        var content: [Summary]
        var hasNext: Bool
    }

    private struct Detail: Decodable {
        struct File: Decodable {
            var id: Int
            var bookType: String?
            var `extension`: String?
            var folderBased: Bool?
            /// false for supplementary files, which aren't readable.
            var book: Bool?
            var primary: Bool?
        }

        var id: Int
        var title: String?
        var authors: [String]?
        var files: [File]?
        var coverUpdatedOn: String?
        var audiobookCoverUpdatedOn: String?
    }

    private struct AudiobookInfo: Decodable {
        struct Track: Decodable { var fileName: String? }
        var tracks: [Track]?
    }

    private static let pageSize = 50
    private static let concurrentDetails = 6

    func books() async throws(RequestError) -> [Book] {
        var ids: [Int] = []
        var page = 0
        while true {
            let result = try await get(Page.self, "app/books", query: ["page": "\(page)", "size": "\(Self.pageSize)"])
            ids += result.content.map(\.id)
            guard result.hasNext else { break }
            page += 1
        }
        return try await details(of: ids)
    }

    /// The list only names each Book's primary file, so each Book's detail is fetched for its Book files.
    private func details(of ids: [Int]) async throws(RequestError) -> [Book] {
        let results = await withTaskGroup(of: (Int, Result<Book, RequestError>).self) { group in
            var results: [Int: Result<Book, RequestError>] = [:]
            var pending = ids.enumerated().makeIterator()
            func addNext() {
                guard let (index, id) = pending.next() else { return }
                group.addTask {
                    do throws(RequestError) { return (index, .success(try await book(id))) } catch { return (index, .failure(error)) }
                }
            }
            for _ in 0 ..< Self.concurrentDetails { addNext() }
            for await (index, result) in group {
                results[index] = result
                addNext()
            }
            return results
        }
        return try ids.indices.map { index throws(RequestError) in try results[index]!.get() }
    }

    private func book(_ id: Int) async throws(RequestError) -> Book {
        let detail = try await get(Detail.self, "app/books/\(id)")
        var files: [BookFile] = []
        for file in detail.files ?? [] where file.book != false {
            let format = Self.format(of: file.bookType)
            files.append(BookFile(id: file.id, format: format, isSupported: try await isSupported(file, format: format, bookID: id)))
        }
        return Book(
            id: detail.id,
            title: detail.title ?? "Untitled",
            authors: detail.authors ?? [],
            files: files,
            primaryFileID: detail.files?.first { $0.primary == true }?.id,
            ebookCover: detail.coverUpdatedOn.map { Cover(bookID: id, kind: .ebook, updatedOn: $0) },
            audiobookCover: detail.audiobookCoverUpdatedOn.map { Cover(bookID: id, kind: .audiobook, updatedOn: $0) }
        )
    }

    private static func format(of bookType: String?) -> BookFile.Format {
        switch bookType {
        case "EPUB": .epub
        case "PDF": .pdf
        case "AUDIOBOOK": .audiobook
        case "MOBI": .mobi
        case "AZW3": .azw3
        case "FB2": .fb2
        case "CBX": .comic
        default: .other
        }
    }

    /// Grimmory files Opus under AUDIOBOOK. A folder audiobook's own extension is absent, so its Tracks are checked.
    private func isSupported(_ file: Detail.File, format: BookFile.Format, bookID: Int) async throws(RequestError) -> Bool {
        switch format {
        case .epub, .pdf: return true
        case .mobi, .azw3, .fb2, .comic, .other: return false
        case .audiobook:
            if file.folderBased == true {
                let info = try await get(AudiobookInfo.self, "audiobooks/\(bookID)/info", query: ["bookType": "AUDIOBOOK"])
                return !(info.tracks ?? []).contains { Self.isOpus($0.fileName) }
            }
            return !Self.isOpus(file.extension.map { "." + $0 })
        }
    }

    private static func isOpus(_ fileName: String?) -> Bool {
        fileName?.lowercased().hasSuffix(".opus") == true
    }

    func image(for cover: Cover) async -> Data? {
        let name = cover.kind == .audiobook ? "audiobook-thumbnail" : "thumbnail"
        guard let request = request("media/book/\(cover.bookID)/\(name)", query: [:]),
              let (status, data) = try? await account.send(request), status == 200
        else { return nil }
        return data
    }

    private func get<T: Decodable>(_ type: T.Type, _ path: String, query: [String: String] = [:]) async throws(RequestError) -> T {
        guard let request = request(path, query: query) else { throw .signedOut }
        let (status, data) = try await account.send(request)
        switch status {
        case 200:
            do {
                return try JSONDecoder().decode(type, from: data)
            } catch {
                throw .serverChanged
            }
        default: throw .serverChanged
        }
    }

    private func request(_ path: String, query: [String: String]) -> URLRequest? {
        guard var url = server?.appending(path: "api/v1/\(path)") else { return nil }
        if !query.isEmpty {
            url.append(queryItems: query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) })
        }
        return URLRequest(url: url)
    }
}
