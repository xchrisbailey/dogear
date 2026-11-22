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
                progressPercent: location.throughBook * 100,
                contentSourceProgressPercent: location.throughChapter * 100
            ))
        case let .pdf(location):
            // The Server parses `positionData` as an integer for PDFs.
            body = FileProgressUpdate(fileProgress: .init(
                bookFileId: position.bookFileID,
                positionData: String(location.page),
                progressPercent: location.throughBook * 100
            ))
        case let .audiobook(location):
            body = FileProgressUpdate(fileProgress: .init(
                bookFileId: position.bookFileID,
                positionData: String(location.milliseconds),
                positionHref: String(location.trackIndex),
                // Rounded to 0.1 like the web player's saves.
                progressPercent: (location.throughBook * 1000).rounded() / 10
            ))
        }
        var request = try await request(bookID: bookID)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(body)
        try await account.deliver(request)
    }

    /// The Book file's Shared position in `format`, or nil if it was never read anywhere.
    public func latest(_ format: BookFile.Format, bookID: Int, bookFileID: Int) async throws(RequestError) -> Position? {
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
    static func date(_ text: String) -> Date? {
        (try? Date(text, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true)))
            ?? (try? Date(text, strategy: .iso8601))
    }

    /// Only `fileProgress`: the deprecated per-type fields would be saved over it.
    private struct FileProgressUpdate: Encodable {
        struct FileProgress: Encodable {
            var bookFileId: Int
            var positionData: String?
            var positionHref: String?
            var progressPercent: Double
            var contentSourceProgressPercent: Double?
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

        struct PDF: Decodable {
            var page: Int?
            var percentage: Double?
            var updatedAt: String?
        }

        struct Audiobook: Decodable {
            var positionMs: Int?
            var trackIndex: Int?
            var percentage: Double?
            var updatedAt: String?
        }

        var epubProgress: EPUB?
        var pdfProgress: PDF?
        var audiobookProgress: Audiobook?

        /// Compared by the format's own `updatedAt` rather than the Book's `lastReadTime`, which
        /// also moves when another of the Book's files is read.
        func position(_ format: BookFile.Format, bookFileID: Int) -> Position? {
            switch format {
            case .epub, .mobi, .azw3, .fb2:
                // Grimmory keeps MOBI, AZW3 and FB2 Positions as EPUB ones, and so does Dogear.
                // The Server keeps it per Book and drops the spot in the Chapter, so `throughChapter` is 0.
                guard let epub = epubProgress, let href = epub.href,
                      let recordedAt = epub.updatedAt.flatMap(SharedPositions.date)
                else { return nil }
                let location = EPUBLocation(
                    href: String(href.prefix { $0 != "#" }),
                    throughChapter: 0,
                    throughBook: (epub.percentage ?? 0) / 100,
                    cfi: epub.cfi
                )
                return Position(bookFileID: bookFileID, location: .epub(location), recordedAt: recordedAt)
            case .pdf:
                guard let pdf = pdfProgress, let page = pdf.page,
                      let recordedAt = pdf.updatedAt.flatMap(SharedPositions.date)
                else { return nil }
                let location = PDFLocation(page: page, throughBook: (pdf.percentage ?? 0) / 100)
                return Position(bookFileID: bookFileID, location: .pdf(location), recordedAt: recordedAt)
            case .audiobook:
                guard let audiobook = audiobookProgress, let milliseconds = audiobook.positionMs,
                      let recordedAt = audiobook.updatedAt.flatMap(SharedPositions.date)
                else { return nil }
                let location = AudiobookLocation(
                    // The web player only saves a Track for folder audiobooks.
                    trackIndex: audiobook.trackIndex ?? 0,
                    milliseconds: milliseconds,
                    throughBook: (audiobook.percentage ?? 0) / 100
                )
                return Position(bookFileID: bookFileID, location: .audiobook(location), recordedAt: recordedAt)
            case .comic, .other:
                // Dogear can't open these, so it never reads or records Positions in them.
                return nil
            }
        }
    }
}
