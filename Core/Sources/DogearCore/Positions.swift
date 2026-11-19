import Foundation
import SwiftData

/// The reader's Positions, saved on the device the moment they change so a crash never loses a place.
public actor Positions {
    private let cache: PositionCache
    private let clock: any WallClock

    public init(store: PositionStore, clock: any WallClock = SystemClock()) {
        cache = PositionCache(modelContainer: store.container)
        self.clock = clock
    }

    /// Saves `location` as the latest Position in the Book file, stamped with the device time.
    @discardableResult
    public func record(_ location: Position.Location, bookFileID: Int) async throws -> Position {
        let position = Position(bookFileID: bookFileID, location: location, recordedAt: clock.now())
        try await cache.save(position)
        return position
    }

    public func latest(bookFileID: Int) async -> Position? {
        await cache.position(bookFileID: bookFileID)
    }

    /// Drops every Position, so the next account or Server starts clean.
    public func forget() async {
        try? await cache.clear()
    }
}

/// The on-device store for Positions, in Application Support so iOS doesn't purge it.
public struct PositionStore: Sendable {
    let container: ModelContainer

    public init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        container = try ModelContainer(for: StoredPosition.self, configurations: ModelConfiguration(url: url))
    }

    public static func onDevice() throws -> PositionStore {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return try PositionStore(url: directory.appending(path: "Positions.store"))
    }
}

@Model final class StoredPosition {
    @Attribute(.unique) var bookFileID: Int
    var payload: Data

    init(bookFileID: Int, payload: Data) {
        self.bookFileID = bookFileID
        self.payload = payload
    }
}

@ModelActor actor PositionCache {
    func position(bookFileID: Int) -> Position? {
        guard let stored = stored(bookFileID) else { return nil }
        return try? JSONDecoder().decode(Position.self, from: stored.payload)
    }

    func save(_ position: Position) throws {
        let payload = try JSONEncoder().encode(position)
        if let stored = stored(position.bookFileID) {
            stored.payload = payload
        } else {
            modelContext.insert(StoredPosition(bookFileID: position.bookFileID, payload: payload))
        }
        try modelContext.save()
    }

    func clear() throws {
        try modelContext.delete(model: StoredPosition.self)
        try modelContext.save()
    }

    private func stored(_ bookFileID: Int) -> StoredPosition? {
        var descriptor = FetchDescriptor<StoredPosition>(predicate: #Predicate { $0.bookFileID == bookFileID })
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }
}
