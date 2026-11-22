import Foundation

/// Continue Reading and Continue Listening: the Book files the reader was last in, most recent first.
public struct ContinueRows: Sendable, Equatable {
    public var reading: [ContinueEntry]
    public var listening: [ContinueEntry]

    public init(reading: [ContinueEntry] = [], listening: [ContinueEntry] = []) {
        self.reading = reading
        self.listening = listening
    }
}

/// One Book file to jump back into. Opening it resumes at its Position.
public struct ContinueEntry: Sendable, Equatable, Identifiable {
    public var book: Book
    public var file: BookFile
    /// When the reader was last in it, here or anywhere the Server knows of.
    public var lastRead: Date
    /// The Position recorded on this device, if any.
    public var position: Position?

    public var id: Int { file.id }
}

/// The Books the Server lists in its continue rows, each with its `lastReadTime`, kept for offline use.
struct ServerContinueRows: Codable, Sendable {
    struct Row: Codable, Sendable {
        var bookID: Int
        var lastRead: Date
    }

    var reading: [Row] = []
    var listening: [Row] = []

    /// Merges the Server's rows with Positions recorded on this device, which may be newer than
    /// anything the Server has seen (offline, or still in the Outbox).
    func rows(books: [Book], positions: [Position], limit: Int) -> ContinueRows {
        ContinueRows(
            reading: entries(reading, kind: .ebook, books: books, positions: positions, limit: limit),
            listening: entries(listening, kind: .audiobook, books: books, positions: positions, limit: limit)
        )
    }

    enum Kind {
        case ebook, audiobook

        /// Preferred first: EPUB reflows, so it beats a PDF of the same Book.
        var formats: [BookFile.Format] {
            switch self {
            case .ebook: BookFile.Format.ebooks
            case .audiobook: [.audiobook]
            }
        }
    }

    private func entries(_ rows: [Row], kind: Kind, books: [Book], positions: [Position], limit: Int) -> [ContinueEntry] {
        let local = Dictionary(
            positions.filter { kind.formats.contains($0.location.format) }.map { ($0.bookFileID, $0) },
            uniquingKeysWith: { $0.recordedAt >= $1.recordedAt ? $0 : $1 }
        )
        let serverTimes = Dictionary(rows.map { ($0.bookID, $0.lastRead) }, uniquingKeysWith: { first, _ in first })

        var entries: [ContinueEntry] = []
        for book in books where serverTimes[book.id] != nil || book.files.contains(where: { local[$0.id] != nil }) {
            let files = book.files.filter { $0.isSupported && kind.formats.contains($0.format) }
            let newestLocal = files.compactMap { local[$0.id] }.max { $0.recordedAt < $1.recordedAt }
            guard let file = files.first(where: { $0.id == newestLocal?.bookFileID })
                ?? kind.formats.lazy.compactMap({ format in files.first { $0.format == format } }).first
            else { continue }
            let serverTime = serverTimes[book.id]
            if let newestLocal, serverTime.map({ newestLocal.recordedAt > $0 }) ?? true {
                // Newer than the Server's row, so it decides, as the Server would once it arrives.
                guard Self.isStartedButUnfinished(newestLocal) else { continue }
            }
            guard let lastRead = [serverTime, newestLocal?.recordedAt].compactMap(\.self).max() else { continue }
            entries.append(ContinueEntry(book: book, file: file, lastRead: lastRead, position: newestLocal))
        }
        return Array(entries.sorted { $0.lastRead > $1.lastRead }.prefix(limit))
    }

    /// Grimmory lists a Book once it's more than 0.1 % in and until it's 99.5 % through.
    private static func isStartedButUnfinished(_ position: Position) -> Bool {
        let throughBook = position.location.throughBook
        return throughBook > 0.001 && throughBook < 0.995
    }
}
