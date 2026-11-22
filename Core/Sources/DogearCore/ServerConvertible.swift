import Foundation

/// A Book's MOBI, AZW3 or FB2 as the Server serves it to its web reader, so it opens without a
/// Download and without the `canDownload` permission. The reader converts it to an EPUB (ADR 0005).
public struct ServerConvertible: Sendable {
    private let account: Account
    private let url: URL

    public let bookID: Int
    public let format: BookFile.Format

    /// nil when signed out, or when `format` isn't one Dogear converts.
    public init?(account: Account, bookID: Int, format: BookFile.Format) async {
        guard format.isConvertedToEPUB, let bookType = format.bookType,
              let server = await account.session?.server
        else { return nil }
        self.account = account
        self.bookID = bookID
        self.format = format
        // bookType picks this format when the Book's primary file is another one.
        url = server.appending(path: "api/v1/books/\(bookID)/content")
            .appending(queryItems: [URLQueryItem(name: "bookType", value: bookType)])
    }

    /// The whole file: converting reads all of it.
    public func contents() async throws(RequestError) -> Data {
        try await account.fetchData(URLRequest(url: url))
    }
}
