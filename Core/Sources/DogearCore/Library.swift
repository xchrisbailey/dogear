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

    /// Fetches the latest Books, libraries and shelves and replaces the cached copy. On failure the cache is left as it was.
    public func refresh() async throws(RequestError) -> [Book] {
        let client = await client()
        let libraries = try await client.libraries()
        let shelves = try await client.shelves()
        var books = try await client.books(cached: await cache.books())
        for index in books.indices {
            books[index].shelfIDs = shelves.filter { $0.bookIDs.contains(books[index].id) }.map(\.shelf.id)
        }
        let navigation = Navigation(libraries: libraries, shelves: shelves.map(\.shelf))
        // A failed save only costs the offline copy; the fresh list is still worth showing.
        try? await cache.replace(books: books, navigation: navigation)
        try await refreshContinueRows()
        return books
    }

    /// The most Books each continue row shows.
    static let continueLimit = 10

    /// Fetches the Server's Continue Reading and Continue Listening rows, which move whenever a
    /// Position is saved here or elsewhere. On failure the cached rows are left as they were.
    public func refreshContinueRows() async throws(RequestError) {
        let client = await client()
        let rows = ServerContinueRows(
            reading: try await client.continueRows("continue-reading", limit: Self.continueLimit),
            listening: try await client.continueRows("continue-listening", limit: Self.continueLimit)
        )
        try? await cache.replace(rows)
    }

    /// Continue Reading and Continue Listening from the cached Books, moved on by `positions`
    /// recorded on this device, so the rows are current offline and before the Outbox is flushed.
    public func continueRows(including positions: [Position]) async -> ContinueRows {
        await cache.continueRows().rows(books: await cache.books(), positions: positions, limit: Self.continueLimit)
    }

    /// The Grimmory libraries and shelves from the last successful refresh.
    public func navigation() async -> Navigation {
        await cache.navigation()
    }

    /// The cached Books in `scope` whose title or authors match every word of `search`,
    /// so browsing and searching work the same offline.
    public func books(
        in scope: BookScope = .everything, matching search: String = "", showing kind: BookKind = .all
    ) async -> [Book] {
        let words = search.split(whereSeparator: \.isWhitespace)
        return await cache.books().filter { book in
            scope.contains(book) && kind.contains(book) && words.allSatisfy { book.matches(String($0)) }
        }
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

    private struct LibrarySummary: Decodable {
        var id: Int
        var name: String
    }

    /// The web endpoint, because the app one answers 500 to readers who aren't admins.
    func libraries() async throws(RequestError) -> [ServerLibrary] {
        try await get([LibrarySummary].self, "libraries").map { ServerLibrary(id: $0.id, name: $0.name) }
    }

    private struct ContinueSummary: Decodable {
        var id: Int
        var lastReadTime: String?
    }

    /// Ordered by the Server, most recent first.
    func continueRows(_ list: String, limit: Int) async throws(RequestError) -> [ServerContinueRows.Row] {
        try await get([ContinueSummary].self, "app/books/\(list)", query: ["limit": "\(limit)"]).compactMap { summary in
            guard let lastRead = summary.lastReadTime.flatMap(SharedPositions.date) else { return nil }
            return ServerContinueRows.Row(bookID: summary.id, lastRead: lastRead)
        }
    }

    private struct ShelfSummary: Decodable {
        var id: Int
        var name: String
    }

    /// Each shelf with its Books, from the shelf-filtered list, which is verified live; the shelves in Book details aren't.
    func shelves() async throws(RequestError) -> [(shelf: Shelf, bookIDs: Set<Int>)] {
        var shelves: [(shelf: Shelf, bookIDs: Set<Int>)] = []
        for summary in try await get([ShelfSummary].self, "app/shelves") {
            let ids = try await bookIDs(query: ["shelfId": "\(summary.id)"])
            shelves.append((Shelf(id: summary.id, name: summary.name), Set(ids)))
        }
        return shelves
    }

    private struct Detail: Decodable {
        struct File: Decodable {
            var id: Int
            var bookType: String?
            var fileSizeKb: Int?
            var `extension`: String?
            var folderBased: Bool?
            /// false for supplementary files, which aren't readable.
            var book: Bool?
            var primary: Bool?
        }

        var id: Int
        var title: String?
        var libraryId: Int?
        var authors: [String]?
        var files: [File]?
        var coverUpdatedOn: String?
        var audiobookCoverUpdatedOn: String?
        /// A percentage.
        var readProgress: Double?
        var lastReadTime: String?
    }

    private struct AudiobookInfo: Decodable {
        struct Track: Decodable { var fileName: String? }
        var tracks: [Track]?
    }

    private static let pageSize = 50
    private static let concurrentDetails = 6

    /// Every Book's detail is fetched on each refresh. The list's summaries can't say which are
    /// unchanged: they describe only the primary file, and attaching or detaching another Book file
    /// on the Server changes none of their fields (`addedOn`, `coverUpdatedOn`, `primaryFileId`…).
    func books(cached: [Book]) async throws(RequestError) -> [Book] {
        try await details(of: try await bookIDs(query: [:]), cached: cached)
    }

    private func bookIDs(query: [String: String]) async throws(RequestError) -> [Int] {
        var ids: [Int] = []
        var page = 0
        while true {
            let paging = ["page": "\(page)", "size": "\(Self.pageSize)"]
            let result = try await get(Page.self, "app/books", query: query.merging(paging) { _, paging in paging })
            ids += result.content.map(\.id)
            guard result.hasNext else { break }
            page += 1
        }
        return ids
    }

    /// The list only names each Book's primary file, so each Book's detail is fetched for its Book files.
    /// One Book's failure doesn't fail the rest: a Book deleted or hidden since the list was
    /// fetched is left out, and one whose detail can't be read keeps its cached copy.
    private func details(of ids: [Int], cached: [Book]) async throws(RequestError) -> [Book] {
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
        let cached = Dictionary(cached.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var books: [Book] = []
        for (index, id) in ids.enumerated() {
            switch results[index] {
            case let .success(book)?: books.append(book)
            case .failure(.notFound)?, .failure(.forbidden)?: continue
            case .failure(.serverChanged)?: if let book = cached[id] { books.append(book) }
            // Offline or signed out: the whole refresh fails and the cache stays as it was.
            case let .failure(error)?: throw error
            case nil: continue
            }
        }
        return books
    }

    private func book(_ id: Int) async throws(RequestError) -> Book {
        let detail = try await get(Detail.self, "app/books/\(id)")
        var files: [BookFile] = []
        for file in detail.files ?? [] where file.book != false {
            let format = Self.format(of: file.bookType)
            files.append(BookFile(
                id: file.id, format: format, isSupported: try await isSupported(file, format: format, bookID: id),
                sizeKB: file.fileSizeKb
            ))
        }
        return Book(
            id: detail.id,
            title: detail.title ?? "Untitled",
            authors: detail.authors ?? [],
            files: files,
            primaryFileID: detail.files?.first { $0.primary == true }?.id,
            ebookCover: detail.coverUpdatedOn.map { Cover(bookID: id, kind: .ebook, updatedOn: $0) },
            audiobookCover: detail.audiobookCoverUpdatedOn.map { Cover(bookID: id, kind: .audiobook, updatedOn: $0) },
            libraryID: detail.libraryId,
            serverThroughBook: detail.readProgress.map { $0 / 100 },
            serverLastRead: detail.lastReadTime.flatMap(SharedPositions.date)
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

    private func get<T: Decodable & Sendable>(_ type: T.Type, _ path: String, query: [String: String] = [:]) async throws(RequestError) -> T {
        guard let request = request(path, query: query) else { throw .signedOut }
        return try await account.fetch(type, request)
    }

    private func request(_ path: String, query: [String: String]) -> URLRequest? {
        guard var url = server?.appending(path: "api/v1/\(path)") else { return nil }
        if !query.isEmpty {
            url.append(queryItems: query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) })
        }
        return URLRequest(url: url)
    }
}
