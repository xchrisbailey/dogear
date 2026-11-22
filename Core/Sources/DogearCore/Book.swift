import Foundation

/// One title in the Grimmory library, holding one or more Book files, exactly as the Server groups them.
public struct Book: Codable, Sendable, Equatable, Identifiable {
    public var id: Int
    public var title: String
    public var authors: [String]
    public var files: [BookFile]
    public var primaryFileID: Int?
    public var ebookCover: Cover?
    public var audiobookCover: Cover?
    /// The Grimmory library holding the Book.
    public var libraryID: Int?
    /// The reader's shelves holding the Book.
    public var shelfIDs: [Int]
    /// 0…1 through the Book as the Server last saw it, and when; nil if never read anywhere.
    public var serverThroughBook: Double?
    public var serverLastRead: Date?

    public init(
        id: Int, title: String, authors: [String], files: [BookFile], primaryFileID: Int?,
        ebookCover: Cover?, audiobookCover: Cover?, libraryID: Int? = nil, shelfIDs: [Int] = [],
        serverThroughBook: Double? = nil, serverLastRead: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.authors = authors
        self.files = files
        self.primaryFileID = primaryFileID
        self.ebookCover = ebookCover
        self.audiobookCover = audiobookCover
        self.libraryID = libraryID
        self.shelfIDs = shelfIDs
        self.serverThroughBook = serverThroughBook
        self.serverLastRead = serverLastRead
    }

    /// How far through the Book the reader is: the newest of `positions` recorded in its Book
    /// files, unless the Server has seen newer reading of it. nil if it was never read.
    public func throughBook(including positions: [Position]) -> Double? {
        let ids = Set(files.map(\.id))
        let local = positions.filter { ids.contains($0.bookFileID) }.max { $0.recordedAt < $1.recordedAt }
        guard let local else { return serverThroughBook }
        if let serverThroughBook, let serverLastRead, serverLastRead > local.recordedAt { return serverThroughBook }
        return local.location.throughBook
    }

    /// Each format once, in Grimmory's file order.
    public var formats: [BookFile.Format] {
        files.reduce(into: []) { formats, file in
            if !formats.contains(file.format) { formats.append(file.format) }
        }
    }

    /// The ebook files a tap can open: the one that reflows best, in `BookFile.Format.ebooks`
    /// order, and a PDF, whose fixed pages a reader may want instead. A MOBI beside an EPUB of
    /// the same Book adds nothing, so it isn't offered.
    public var readableFiles: [BookFile] {
        let supported = files.filter(\.isSupported)
        let reflowing = BookFile.Format.ebooks.filter { $0 != .pdf }.lazy
            .compactMap { format in supported.first { $0.format == format } }.first
        let pdf = supported.first { $0.format == .pdf }
        return [reflowing, pdf].compactMap(\.self)
    }

    /// Ignores case and accents, so "bronte" finds "Brontë".
    func matches(_ word: String) -> Bool {
        ([title] + authors).contains { $0.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    /// The cover to show in lists: the audiobook cover when the Book is primarily an audiobook.
    public var cover: Cover? {
        let primary = files.first { $0.id == primaryFileID } ?? files.first
        return primary?.format == .audiobook ? audiobookCover ?? ebookCover : ebookCover ?? audiobookCover
    }
}

public struct BookFile: Codable, Sendable, Equatable, Identifiable {
    public enum Format: String, Codable, Sendable {
        case epub, pdf, audiobook, mobi, azw3, fb2, comic, other
    }

    public var id: Int
    public var format: Format
    /// False for formats Dogear can't open (comics, Opus audio, and anything Grimmory doesn't name).
    public var isSupported: Bool
    /// The file's size on the Server, in kilobytes. nil for Books cached before sizes were kept.
    public var sizeKB: Int?

    public init(id: Int, format: Format, isSupported: Bool, sizeKB: Int? = nil) {
        self.id = id
        self.format = format
        self.isSupported = isSupported
        self.sizeKB = sizeKB
    }
}

extension BookFile.Format {
    /// Ebook formats, most preferred first, for picking which of a Book's files a tap opens:
    /// EPUB reflows best, then the formats converted to it, and a PDF last.
    public static let ebooks: [BookFile.Format] = [.epub, .azw3, .mobi, .fb2, .pdf]

    /// MOBI, AZW3 and FB2 open in the EPUB reader, converted to an EPUB on the device (ADR 0005).
    /// Their Positions are EPUB Positions, which Grimmory stores the same way for them.
    public var isConvertedToEPUB: Bool {
        [.mobi, .azw3, .fb2].contains(self)
    }

    /// The Server's name for the format, as `bookType` takes it.
    var bookType: String? {
        switch self {
        case .epub: "EPUB"
        case .pdf: "PDF"
        case .audiobook: "AUDIOBOOK"
        case .mobi: "MOBI"
        case .azw3: "AZW3"
        case .fb2: "FB2"
        case .comic: "CBX"
        case .other: nil
        }
    }
}

/// A cover image Grimmory holds for a Book. `updatedOn` changes when the image does.
public struct Cover: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable {
        case ebook, audiobook
    }

    public var bookID: Int
    public var kind: Kind
    public var updatedOn: String

    public init(bookID: Int, kind: Kind, updatedOn: String) {
        self.bookID = bookID
        self.kind = kind
        self.updatedOn = updatedOn
    }
}
