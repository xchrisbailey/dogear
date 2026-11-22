import Foundation

/// The fake Server's book content endpoint, which the web reader loads PDFs, MOBIs, AZW3s and FB2s from.
extension FakeGrimmory {
    static func content(_ request: Request, state: State) -> FakeServer.Reply? {
        let parts = request.path.split(separator: "/").map(String.init)
        guard request.method == "GET", parts.count == 5, parts.starts(with: ["api", "v1", "books"]), parts[4] == "content",
              let bookID = Int(parts[3])
        else { return nil }
        // Header only: Grimmory answers `?token=` here with a 401.
        guard isAuthorized(request, state: state) else {
            return fixture("error-401-unauthenticated", status: 401)
        }
        guard let book = state.library.first(where: { $0.id == bookID }) else {
            return fixture("error-404-book", status: 404)
        }
        let primary = book.detailJSON["primaryFileType"] as? String
        let requested = request.query["bookType"] ?? primary
        let files = book.detailJSON["files"] as? [[String: Any]] ?? []
        if let requested, ["MOBI", "AZW3", "FB2"].contains(requested) {
            guard files.contains(where: { $0["bookType"] as? String == requested }) else {
                return fixture("error-404-book", status: 404)
            }
            return .response(status: 200, body: contentBytes(bookID: bookID, bookType: requested), contentType: "application/octet-stream")
        }
        guard requested == "PDF" else {
            return .response(status: 200, body: Data("not a pdf".utf8), contentType: "application/epub+zip")
        }
        return .response(status: 200, body: pdfBytes(bookID: bookID), contentType: "application/pdf")
    }

    /// Stand-in MOBI, AZW3 or FB2 bytes, distinct per Book and format.
    static func contentBytes(bookID: Int, bookType: String) -> Data {
        Data("\(bookType) book \(bookID)".utf8)
    }

    /// Stand-in PDF bytes, distinct per Book.
    static func pdfBytes(bookID: Int) -> Data {
        Data("%PDF-1.7 book \(bookID)".utf8)
    }
}
