import Foundation

/// The fake Server's library: Books served through the app API, built from book-detail fixtures.
extension FakeGrimmory {
    struct ShelvedBook: Sendable {
        /// A `book-detail-*` fixture; the list endpoint serves the same object as the summary.
        var detail: String
        /// An `audiobook-info-*` fixture, for Books with a folder audiobook.
        var audiobookInfo: String?
        /// Applied to both fixtures, to vary a real response (e.g. a different file extension).
        var replacing: [String: String] = [:]

        var detailJSON: [String: Any] { FakeGrimmory.json(detail, replacing: replacing) }
        var id: Int { detailJSON["id"] as! Int }
    }

    static let atomicHabits = ShelvedBook(detail: "book-detail-epub")
    static let projectHailMary = ShelvedBook(detail: "book-detail-audiobook-single")
    static let slaughterhouseFive = ShelvedBook(detail: "book-detail-audiobook-folder", audiobookInfo: "audiobook-info-folder")
    static let allSystemsRed = ShelvedBook(detail: "book-detail-azw3")
    static let mobyDick = ShelvedBook(detail: "book-detail-multi-file")

    struct Shelf: Sendable {
        var id: Int
        var name: String
        var bookIDs: [Int]
    }

    func shelve(_ books: [ShelvedBook]) {
        state.withLock { $0.library = books }
    }

    func setShelves(_ shelves: [Shelf]) {
        state.withLock { $0.shelves = shelves }
    }

    static func library(_ request: Request, state: State) -> FakeServer.Reply? {
        let parts = request.path.split(separator: "/").map(String.init)
        guard request.method == "GET", parts.starts(with: ["api", "v1"]) else { return nil }
        let route = Array(parts.dropFirst(2))
        let isLibraryRoute = route.starts(with: ["app", "books"]) || route == ["app", "shelves"] || route == ["libraries"]
            || route.first == "media" || route.first == "audiobooks"
        guard isLibraryRoute else { return nil }
        guard isAuthorized(request, state: state) else {
            return fixture("error-401-unauthenticated", status: 401)
        }

        func book(_ id: String) -> ShelvedBook? { state.library.first { String($0.id) == id } }

        switch route {
        case ["libraries"]:
            return fixture("libraries-web")
        case ["app", "shelves"]:
            let shelves = state.shelves.map { shelf -> [String: Any] in
                ["id": shelf.id, "name": shelf.name, "icon": "heart", "bookCount": shelf.bookIDs.count, "publicShelf": false]
            }
            return .response(status: 200, body: data(shelves))
        case ["app", "books"]:
            var books = state.library
            if let shelfID = request.query["shelfId"] {
                let ids = state.shelves.first { String($0.id) == shelfID }?.bookIDs ?? []
                books = books.filter { ids.contains($0.id) }
            }
            return page(of: books, query: request.query)
        case let r where r.count == 3 && r.starts(with: ["app", "books"]):
            guard let book = book(r[2]) else { return fixture("error-404-book", status: 404) }
            return .response(status: 200, body: data(book.detailJSON))
        case let r where r.count == 3 && r[0] == "audiobooks" && r[2] == "info":
            guard let book = book(r[1]), let info = book.audiobookInfo else {
                return fixture("error-404-book", status: 404)
            }
            return fixture(info, replacing: book.replacing)
        case let r where r.count == 4 && r[0] == "media" && r[1] == "book":
            let kind = r[3]
            let updatedKey = kind == "audiobook-thumbnail" ? "audiobookCoverUpdatedOn" : "coverUpdatedOn"
            guard let book = book(r[2]), book.detailJSON[updatedKey] != nil else {
                return fixture("error-404-book", status: 404)
            }
            return .response(status: 200, body: coverBytes(bookID: book.id, kind: kind), contentType: "image/jpeg")
        default:
            return nil
        }
    }

    /// Stand-in image bytes, distinct per Book and cover kind so tests can tell them apart.
    static func coverBytes(bookID: Int, kind: String) -> Data {
        Data("\(kind)-\(bookID)".utf8)
    }

    private static func page(of books: [ShelvedBook], query: [String: String]) -> FakeServer.Reply {
        let size = min(Int(query["size"] ?? "") ?? 50, 50)
        let page = Int(query["page"] ?? "") ?? 0
        let content = books.dropFirst(page * size).prefix(size).map(\.detailJSON)
        let totalPages = (books.count + size - 1) / size
        let body: [String: Any] = [
            "content": Array(content), "page": page, "size": size, "totalElements": books.count,
            "totalPages": totalPages, "hasNext": page + 1 < totalPages, "hasPrevious": page > 0,
        ]
        return .response(status: 200, body: data(body))
    }

    static func json(_ name: String, replacing: [String: String]) -> [String: Any] {
        guard case let .response(_, body, _) = fixture(name, replacing: replacing) else { return [:] }
        return try! JSONSerialization.jsonObject(with: body) as! [String: Any]
    }

    private static func data(_ object: Any) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }
}
