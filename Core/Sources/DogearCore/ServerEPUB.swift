import Foundation

/// A Book's EPUB as the Server serves it, one entry at a time, so it opens without a Download
/// and without the `canDownload` permission.
///
/// The reader's HTTP client sends the requests itself; this signs them, so it shares the
/// Account's single-flight refresh.
public struct ServerEPUB: Sendable {
    private let account: Account

    public let bookID: Int

    /// Entries are paths relative to this, e.g. `META-INF/container.xml`.
    public let baseURL: URL

    /// nil when signed out.
    public init?(account: Account, bookID: Int) async {
        guard let server = await account.session?.server else { return nil }
        self.account = account
        self.bookID = bookID
        // Trailing slash so relative entry paths resolve inside the file endpoint.
        baseURL = server.appending(path: "api/v1/epub/\(bookID)/file/")
    }

    /// Adds the access token, and picks the EPUB in case the Book's primary file is another format.
    public func authorize(_ request: URLRequest) async throws(RequestError) -> URLRequest {
        signed(request, with: try await account.accessToken())
    }

    /// Re-signs `request` after the Server answered it with a 401, refreshing the tokens if no
    /// other request already has.
    public func reauthorize(afterRejecting request: URLRequest) async throws(RequestError) -> URLRequest {
        let sent = request.value(forHTTPHeaderField: "Authorization")?.replacing("Bearer ", with: "", maxReplacements: 1) ?? ""
        return signed(request, with: try await account.accessToken(replacing: sent))
    }

    private func signed(_ request: URLRequest, with accessToken: String) -> URLRequest {
        var request = request
        if let url = request.url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            var query = components.queryItems ?? []
            if !query.contains(where: { $0.name == "bookType" }) {
                query.append(URLQueryItem(name: "bookType", value: "EPUB"))
            }
            components.queryItems = query
            request.url = components.url ?? url
        }
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }
}
