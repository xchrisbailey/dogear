import Foundation

/// The fake Server's EPUB file endpoint: entries from inside a Book's EPUB, served one by one.
extension FakeGrimmory {
    static func epub(_ request: Request, state: State) -> FakeServer.Reply? {
        let parts = request.path.split(separator: "/").map(String.init)
        guard request.method == "GET" || request.method == "HEAD",
              parts.count > 5, parts.starts(with: ["api", "v1", "epub"]), parts[4] == "file"
        else { return nil }
        guard isAuthorized(request, state: state) else {
            return fixture("error-401-unauthenticated", status: 401)
        }
        let book = state.library.first { String($0.id) == parts[3] }
        let fileTypes = book?.detailJSON["fileTypes"] as? [String] ?? []
        // Without bookType the Server serves the primary file, which may not be the EPUB.
        guard fileTypes.contains("EPUB"), request.query["bookType"] == "EPUB" else {
            return fixture("error-404-epub-file", status: 404)
        }
        let entry = parts.dropFirst(5).joined(separator: "/")
        return .response(status: 200, body: entryBytes(bookID: parts[3], entry: entry), contentType: "application/xhtml+xml")
    }

    /// Stand-in entry bytes, distinct per Book and entry.
    static func entryBytes(bookID: String, entry: String) -> Data {
        Data("\(bookID)/\(entry)".utf8)
    }
}
