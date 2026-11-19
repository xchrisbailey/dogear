import Foundation

/// Where the reader is in one Book file, as recorded on this device.
public struct Position: Codable, Sendable, Equatable {
    public enum Location: Codable, Sendable, Equatable {
        case epub(EPUBLocation)
        case pdf(PDFLocation)
        case audiobook(AudiobookLocation)

        public var format: BookFile.Format {
            switch self {
            case .epub: .epub
            case .pdf: .pdf
            case .audiobook: .audiobook
            }
        }

        /// 0…1 through the whole Book file.
        public var throughBook: Double {
            switch self {
            case let .epub(location): location.throughBook
            case let .pdf(location): location.throughBook
            case let .audiobook(location): location.throughBook
            }
        }

        /// Whether `other` is this spot as the Server hands it back: it keeps less than the
        /// device records (no reader state, no spot in the Chapter), so only what it keeps is compared.
        func isSameSpot(as other: Location) -> Bool {
            switch (self, other) {
            case let (.epub(a), .epub(b)):
                if let cfiA = a.cfi, let cfiB = b.cfi { return cfiA == cfiB }
                // Percentages come back rounded.
                return a.href == b.href && abs(a.throughBook - b.throughBook) < 0.0005
            case let (.pdf(a), .pdf(b)):
                return a.page == b.page
            case let (.audiobook(a), .audiobook(b)):
                return a.trackIndex == b.trackIndex && a.milliseconds == b.milliseconds
            default:
                return false
            }
        }
    }

    public var bookFileID: Int
    public var location: Location
    /// Device time; the conflict rule (ADR 0002) compares it with the Server's `lastReadTime`.
    public var recordedAt: Date

    public init(bookFileID: Int, location: Location, recordedAt: Date) {
        self.bookFileID = bookFileID
        self.location = location
        self.recordedAt = recordedAt
    }
}

/// A spot in an EPUB, in the shape the Shared position needs plus what the reader needs to resume exactly.
public struct EPUBLocation: Codable, Sendable, Equatable {
    /// The resource (Chapter file) within the EPUB, without a fragment.
    public var href: String
    /// 0…1 through the resource.
    public var throughChapter: Double
    /// 0…1 through the whole Book file.
    public var throughBook: Double
    /// Point CFI of the start of the visible range. nil when the reader couldn't generate one
    /// (the EPUB's spine couldn't be read, or the page wasn't ready to run scripts), or when the
    /// Shared position it came from had none.
    public var cfi: String?
    /// The reader's own serialised location, for resuming exactly on this device. Opaque to Core.
    public var readerState: String?

    public init(href: String, throughChapter: Double, throughBook: Double, cfi: String? = nil, readerState: String? = nil) {
        self.href = href
        self.throughChapter = throughChapter
        self.throughBook = throughBook
        self.cfi = cfi
        self.readerState = readerState
    }

    // Positions and the Outbox are stored with the names these fields had before.
    private enum CodingKeys: String, CodingKey {
        case href, cfi, readerState
        case throughChapter = "chapterProgress"
        case throughBook = "bookProgress"
    }
}

/// A page in a PDF, in the shape Grimmory's web reader shares.
public struct PDFLocation: Codable, Sendable, Equatable {
    /// 1-based, as the web reader counts.
    public var page: Int
    /// 0…1 through the whole Book file; the web reader uses page ÷ page count.
    public var throughBook: Double

    public init(page: Int, throughBook: Double) {
        self.page = page
        self.throughBook = throughBook
    }

    // Positions and the Outbox are stored with the names these fields had before.
    private enum CodingKeys: String, CodingKey {
        case page
        case throughBook = "bookProgress"
    }
}

/// A time in an audiobook: a Track and the milliseconds into it. A single-file audiobook is Track 0.
public struct AudiobookLocation: Codable, Sendable, Equatable {
    public var trackIndex: Int
    /// Milliseconds into the Track.
    public var milliseconds: Int
    /// 0…1 through the whole Book file.
    public var throughBook: Double

    public init(trackIndex: Int, milliseconds: Int, throughBook: Double) {
        self.trackIndex = trackIndex
        self.milliseconds = milliseconds
        self.throughBook = throughBook
    }

    // Positions and the Outbox are stored with the names these fields had before.
    private enum CodingKeys: String, CodingKey {
        case trackIndex, milliseconds
        case throughBook = "bookProgress"
    }
}
