import Foundation

/// Reads and writes Shared positions through the Server's app progress endpoint, so Grimmory's
/// web reader and Dogear pick up where the other left off.
public struct SharedPositions: Sendable {
    private let account: Account

    public init(account: Account) {
        self.account = account
    }

    /// Sends `position` as the Book file's Shared position. The Server stamps it with its own time.
    public func push(_ position: Position, bookID: Int) async throws(RequestError) {
        let body: FileProgressUpdate
        switch position.location {
        case let .epub(location):
            body = FileProgressUpdate(fileProgress: .init(
                bookFileId: position.bookFileID,
                positionData: location.cfi,
                positionHref: location.href,
                progressPercent: location.bookProgress * 100,
                contentSourceProgressPercent: location.chapterProgress * 100
            ))
        }
        var request = try await request(bookID: bookID)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(body)
        try await account.deliver(request)
    }

    /// The Book file's Shared position in `format`, or nil if it was never read anywhere.
    public func latest(_ format: Position.Format, bookID: Int, bookFileID: Int) async throws(RequestError) -> Position? {
        try await progress(bookID: bookID).position(format, bookFileID: bookFileID)
    }

    /// Everything the Server holds for the Book, so one fetch serves each of its Book files.
    func progress(bookID: Int) async throws(RequestError) -> Progress {
        try await account.fetch(Progress.self, try await request(bookID: bookID))
    }

    private func request(bookID: Int) async throws(RequestError) -> URLRequest {
        guard let server = await account.session?.server else { throw .signedOut }
        return URLRequest(url: server.appending(path: "api/v1/app/books/\(bookID)/progress"))
    }

    // Grimmory sends Instants, with fractional seconds only when they're non-zero.
    fileprivate static func date(_ text: String) -> Date? {
        (try? Date(text, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true)))
            ?? (try? Date(text, strategy: .iso8601))
    }

    /// Only `fileProgress`: the deprecated per-type fields would be saved over it.
    private struct FileProgressUpdate: Encodable {
        struct FileProgress: Encodable {
            var bookFileId: Int
            var positionData: String?
            var positionHref: String
            var progressPercent: Double
            var contentSourceProgressPercent: Double
        }

        var fileProgress: FileProgress
    }

    /// The Server answers reads with its older per-format objects, each stamped `updatedAt`,
    /// not the `fileProgress` shape it's written with.
    struct Progress: Decodable {
        struct EPUB: Decodable {
            var cfi: String?
            var href: String?
            var percentage: Double?
            var updatedAt: String?
        }

        var epubProgress: EPUB?

        /// Compared by the format's own `updatedAt` rather than the Book's `lastReadTime`, which
        /// also moves when another of the Book's files is read.
        func position(_ format: Position.Format, bookFileID: Int) -> Position? {
            switch format {
            case .epub:
                // The Server keeps it per Book and drops in-chapter progress, so `chapterProgress` is 0.
                guard let epub = epubProgress, let href = epub.href,
                      let recordedAt = epub.updatedAt.flatMap(SharedPositions.date)
                else { return nil }
                let location = EPUBLocation(
                    href: String(href.prefix { $0 != "#" }),
                    chapterProgress: 0,
                    bookProgress: (epub.percentage ?? 0) / 100,
                    cfi: epub.cfi
                )
                return Position(bookFileID: bookFileID, location: .epub(location), recordedAt: recordedAt)
            }
        }
    }
}
