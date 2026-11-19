import Foundation

/// Where the reader is in one Book file, as recorded on this device.
public struct Position: Codable, Sendable, Equatable {
    public enum Location: Codable, Sendable, Equatable {
        case epub(EPUBLocation)
        case pdf(PDFLocation)
        case audiobook(AudiobookLocation)

        public var format: Format {
            switch self {
            case .epub: .epub
            case .pdf: .pdf
            case .audiobook: .audiobook
            }
        }
    }

    public enum Format: Sendable {
        case epub
        case pdf
        case audiobook
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
    public var chapterProgress: Double
    /// 0…1 through the whole Book file.
    public var bookProgress: Double
    /// Point CFI of the start of the visible range; nil until the CFI bridge (#6) fills it in.
    public var cfi: String?
    /// The reader's own serialised location, for resuming exactly on this device. Opaque to Core.
    public var readerState: String?

    public init(href: String, chapterProgress: Double, bookProgress: Double, cfi: String? = nil, readerState: String? = nil) {
        self.href = href
        self.chapterProgress = chapterProgress
        self.bookProgress = bookProgress
        self.cfi = cfi
        self.readerState = readerState
    }
}

/// A page in a PDF, in the shape Grimmory's web reader shares.
public struct PDFLocation: Codable, Sendable, Equatable {
    /// 1-based, as the web reader counts.
    public var page: Int
    /// 0…1 through the whole Book file; the web reader uses page ÷ page count.
    public var bookProgress: Double

    public init(page: Int, bookProgress: Double) {
        self.page = page
        self.bookProgress = bookProgress
    }
}

/// A time in an audiobook: a Track and the milliseconds into it. A single-file audiobook is Track 0.
public struct AudiobookLocation: Codable, Sendable, Equatable {
    public var trackIndex: Int
    /// Milliseconds into the Track.
    public var milliseconds: Int
    /// 0…1 through the whole Book file.
    public var bookProgress: Double

    public init(trackIndex: Int, milliseconds: Int, bookProgress: Double) {
        self.trackIndex = trackIndex
        self.milliseconds = milliseconds
        self.bookProgress = bookProgress
    }
}
