import Foundation
import SwiftData

/// The on-device copy of the library (Books and cover images), so it can be browsed offline.
public struct LibraryStore: Sendable {
    let container: ModelContainer

    public init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        container = try ModelContainer(
            for: CachedBook.self, CachedCover.self,
            configurations: ModelConfiguration(url: url)
        )
    }

    /// The app's store in Application Support, which iOS doesn't purge.
    public static func onDevice() throws -> LibraryStore {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return try LibraryStore(url: directory.appending(path: "Library.store"))
    }
}

@Model final class CachedBook {
    @Attribute(.unique) var id: Int
    var order: Int
    var payload: Data

    init(id: Int, order: Int, payload: Data) {
        self.id = id
        self.order = order
        self.payload = payload
    }
}

@Model final class CachedCover {
    @Attribute(.unique) var key: String
    @Attribute(.externalStorage) var image: Data

    init(key: String, image: Data) {
        self.key = key
        self.image = image
    }
}

@ModelActor actor LibraryCache {
    func books() -> [Book] {
        let cached = (try? modelContext.fetch(FetchDescriptor<CachedBook>(sortBy: [SortDescriptor(\.order)]))) ?? []
        return cached.compactMap { try? JSONDecoder().decode(Book.self, from: $0.payload) }
    }

    /// Replaces the whole list, so Books removed on the Server disappear here too.
    func replaceBooks(with books: [Book]) throws {
        try modelContext.delete(model: CachedBook.self)
        for (order, book) in books.enumerated() {
            modelContext.insert(CachedBook(id: book.id, order: order, payload: try JSONEncoder().encode(book)))
        }
        try modelContext.save()
    }

    func image(for cover: Cover) -> Data? {
        let key = Self.key(cover)
        var descriptor = FetchDescriptor<CachedCover>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first?.image
    }

    func store(_ image: Data, for cover: Cover) throws {
        modelContext.insert(CachedCover(key: Self.key(cover), image: image))
        try modelContext.save()
    }

    func clear() throws {
        try modelContext.delete(model: CachedBook.self)
        try modelContext.delete(model: CachedCover.self)
        try modelContext.save()
    }

    private static func key(_ cover: Cover) -> String {
        "\(cover.bookID)/\(cover.kind.rawValue)/\(cover.updatedOn)"
    }
}
