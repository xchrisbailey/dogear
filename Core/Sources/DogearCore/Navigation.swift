import Foundation

/// How the reader has organised Books in Grimmory: its libraries and shelves.
public struct Navigation: Codable, Sendable, Equatable {
    public var libraries: [ServerLibrary]
    public var shelves: [Shelf]

    public init(libraries: [ServerLibrary] = [], shelves: [Shelf] = []) {
        self.libraries = libraries
        self.shelves = shelves
    }

    public func contains(_ scope: BookScope) -> Bool {
        switch scope {
        case .everything: true
        case let .library(id): libraries.contains { $0.id == id }
        case let .shelf(id): shelves.contains { $0.id == id }
        }
    }
}

/// A library on the Server. Every Book belongs to exactly one.
public struct ServerLibrary: Codable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var name: String

    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

/// One of the reader's shelves on the Server. A Book can be on several.
public struct Shelf: Codable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var name: String

    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

/// Which Books to browse.
public enum BookScope: Hashable, Sendable {
    case everything
    case library(Int)
    case shelf(Int)

    func contains(_ book: Book) -> Bool {
        switch self {
        case .everything: true
        case let .library(id): book.libraryID == id
        case let .shelf(id): book.shelfIDs.contains(id)
        }
    }
}

/// Ebooks or audiobooks. A Book with both kinds of Book file counts as each.
public enum BookKind: Hashable, Sendable, CaseIterable {
    case all, ebooks, audiobooks

    func contains(_ book: Book) -> Bool {
        switch self {
        case .all: true
        case .ebooks: book.files.contains { $0.format != .audiobook }
        case .audiobooks: book.files.contains { $0.format == .audiobook }
        }
    }
}
