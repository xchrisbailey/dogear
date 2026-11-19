import Foundation

/// A Book's PDF as the Server serves it to its web reader, so it opens without a Download
/// and without the `canDownload` permission.
public struct ServerPDF: Sendable {
    private let account: Account
    private let url: URL

    public let bookID: Int

    /// nil when signed out.
    public init?(account: Account, bookID: Int) async {
        guard let server = await account.session?.server else { return nil }
        self.account = account
        self.bookID = bookID
        // bookType picks the PDF when the Book's primary file is another format.
        url = server.appending(path: "api/v1/books/\(bookID)/content")
            .appending(queryItems: [URLQueryItem(name: "bookType", value: "PDF")])
    }

    /// The whole PDF. The reader loads a PDF fully into memory anyway, so there's nothing to
    /// gain from streaming it.
    public func contents() async throws(RequestError) -> Data {
        try await account.fetchData(URLRequest(url: url))
    }
}
