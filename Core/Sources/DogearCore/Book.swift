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

    public init(
        id: Int, title: String, authors: [String], files: [BookFile], primaryFileID: Int?,
        ebookCover: Cover?, audiobookCover: Cover?, libraryID: Int? = nil, shelfIDs: [Int] = []
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
    }

    /// Each format once, in Grimmory's file order.
    public var formats: [BookFile.Format] {
        files.reduce(into: []) { formats, file in
            if !formats.contains(file.format) { formats.append(file.format) }
        }
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
    /// False for formats Dogear can't open (MOBI, AZW, AZW3, FB2, comics, Opus audio).
    public var isSupported: Bool

    public init(id: Int, format: Format, isSupported: Bool) {
        self.id = id
        self.format = format
        self.isSupported = isSupported
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
