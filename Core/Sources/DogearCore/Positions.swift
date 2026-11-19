import Foundation
import SwiftData

/// The reader's Positions, saved on the device the moment they change so a crash never loses a
/// place, and the Outbox of those the Server hasn't accepted yet.
public actor Positions {
    private let cache: PositionCache
    private let clock: any WallClock
    private var flushing: Task<Result<Void, RequestError>, Never>?
    private var observers: [UUID: AsyncStream<Int>.Continuation] = [:]
    private var changeObservers: [UUID: AsyncStream<Void>.Continuation] = [:]

    public init(store: PositionStore, clock: any WallClock = SystemClock()) {
        cache = PositionCache(modelContainer: store.container)
        self.clock = clock
    }

    /// Saves `location` as the latest Position in the Book file, stamped with the device time,
    /// and adds it to the Outbox. Every format records its Positions through here.
    @discardableResult
    public func record(_ location: Position.Location, bookFileID: Int, bookID: Int) async throws -> Position {
        let position = Position(bookFileID: bookFileID, location: location, recordedAt: clock.now())
        try await cache.save(position, outboxBookID: bookID)
        await announceOutboxCount()
        announceChange()
        return position
    }

    /// Saves where the reader landed on opening a Book file, without adding it to the Outbox:
    /// it's where they already were, here or elsewhere.
    @discardableResult
    public func recordLanding(_ location: Position.Location, bookFileID: Int) async throws -> Position {
        let position = Position(bookFileID: bookFileID, location: location, recordedAt: clock.now())
        try await cache.save(position, outboxBookID: nil)
        announceChange()
        return position
    }

    public func latest(bookFileID: Int) async -> Position? {
        await cache.position(bookFileID: bookFileID)
    }

    /// The latest Position in every Book file read on this device.
    public func all() async -> [Position] {
        await cache.positions()
    }

    /// Yields whenever a Position is recorded, adopted from the Server or forgotten.
    public func changes() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let id = UUID()
        changeObservers[id] = continuation
        continuation.onTermination = { _ in Task { await self.removeChangeObserver(id) } }
        return stream
    }

    private func removeChangeObserver(_ id: UUID) {
        changeObservers[id] = nil
    }

    private func announceChange() {
        for observer in changeObservers.values { observer.yield() }
    }

    /// How many Positions are waiting for the Server.
    public func outboxCount() async -> Int {
        await cache.outbox().count
    }

    /// The Outbox count now, then every time it changes.
    public func outboxCountUpdates() async -> AsyncStream<Int> {
        let (stream, continuation) = AsyncStream<Int>.makeStream()
        let id = UUID()
        observers[id] = continuation
        continuation.yield(await outboxCount())
        continuation.onTermination = { _ in Task { await self.removeObserver(id) } }
        return stream
    }

    private func removeObserver(_ id: UUID) {
        observers[id] = nil
    }

    private func announceOutboxCount() async {
        let count = await outboxCount()
        for observer in observers.values { observer.yield(count) }
    }

    /// Pushes the Outbox to the Server, oldest first. Entries stay until the Server accepts them,
    /// so an unreachable Server or an expired sign-in just leaves them for the next flush. An entry
    /// for a Book that's gone or out of the reader's reach is dropped, since it can never be accepted.
    public func flushOutbox(to shared: SharedPositions) async throws(RequestError) {
        // One flush at a time, so an entry is never pushed twice. One already running may have
        // started before the latest Position was recorded, so this one runs after it.
        while let flushing { _ = await flushing.value }
        let task = Task { await flush(to: shared) }
        flushing = task
        try await task.value.get()
    }

    private func flush(to shared: SharedPositions) async -> Result<Void, RequestError> {
        defer { flushing = nil }
        let result = await pushOutbox(to: shared)
        await announceOutboxCount()
        return result
    }

    private func pushOutbox(to shared: SharedPositions) async -> Result<Void, RequestError> {
        // Fetched once per Book before any of its entries are pushed: each push moves the Book's
        // `lastReadTime`, which would make its other Book files' entries look stale.
        var progress: [Int: SharedPositions.Progress] = [:]
        for entry in await cache.outbox() {
            let position = entry.position
            do throws(RequestError) {
                let held: SharedPositions.Progress
                if let fetched = progress[entry.bookID] {
                    held = fetched
                } else {
                    held = try await shared.progress(bookID: entry.bookID)
                    progress[entry.bookID] = held
                }
                if let newer = held.position(position.location.format, bookFileID: position.bookFileID),
                   newer.recordedAt > position.recordedAt {
                    // A Stale entry (ADR 0002): newer reading happened elsewhere, so that's where the reader is.
                    try? await cache.adopt(newer, replacing: position)
                    announceChange()
                    continue
                }
                try await shared.push(position, bookID: entry.bookID)
                try? await cache.removeFromOutbox(position)
            } catch .notFound, .forbidden {
                // The Book is gone or out of the reader's reach, so retrying can never succeed.
                // The Position stays on the device.
                try? await cache.removeFromOutbox(position)
            } catch {
                // Offline, signed out or rate-limited: the rest would fail the same way.
                return .failure(error)
            }
        }
        return .success(())
    }

    /// Drops every Position and the Outbox, so the next account or Server starts clean.
    /// The caller warns about a non-empty Outbox first.
    public func forget() async {
        try? await cache.clear()
        await announceOutboxCount()
        announceChange()
    }
}

/// The on-device store for Positions and the Outbox, in Application Support so iOS doesn't purge it.
public struct PositionStore: Sendable {
    let container: ModelContainer

    public init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        container = try ModelContainer(
            for: StoredPosition.self, OutboxEntry.self, configurations: ModelConfiguration(url: url)
        )
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

/// One per Book file: only the newest unsent Position matters, since newest wins (ADR 0002).
@Model final class OutboxEntry {
    @Attribute(.unique) var bookFileID: Int
    var bookID: Int
    var recordedAt: Date
    var payload: Data

    init(bookFileID: Int, bookID: Int, recordedAt: Date, payload: Data) {
        self.bookFileID = bookFileID
        self.bookID = bookID
        self.recordedAt = recordedAt
        self.payload = payload
    }
}

struct WaitingPosition: Sendable {
    var bookID: Int
    var position: Position
}

@ModelActor actor PositionCache {
    func position(bookFileID: Int) -> Position? {
        guard let stored = stored(bookFileID) else { return nil }
        return try? JSONDecoder().decode(Position.self, from: stored.payload)
    }

    func positions() -> [Position] {
        ((try? modelContext.fetch(FetchDescriptor<StoredPosition>())) ?? []).compactMap {
            try? JSONDecoder().decode(Position.self, from: $0.payload)
        }
    }

    /// Saves the latest Position and, with `outboxBookID`, its Outbox entry in one transaction,
    /// so a crash can't leave one without the other.
    func save(_ position: Position, outboxBookID: Int?) throws {
        let payload = try JSONEncoder().encode(position)
        if let stored = stored(position.bookFileID) {
            stored.payload = payload
        } else {
            modelContext.insert(StoredPosition(bookFileID: position.bookFileID, payload: payload))
        }
        if let bookID = outboxBookID {
            if let entry = entry(position.bookFileID) {
                entry.bookID = bookID
                entry.recordedAt = position.recordedAt
                entry.payload = payload
            } else {
                modelContext.insert(OutboxEntry(
                    bookFileID: position.bookFileID, bookID: bookID, recordedAt: position.recordedAt, payload: payload
                ))
            }
        }
        try modelContext.save()
    }

    /// Oldest first, the order the reading happened in.
    func outbox() -> [WaitingPosition] {
        let descriptor = FetchDescriptor<OutboxEntry>(sortBy: [SortDescriptor(\.recordedAt)])
        return ((try? modelContext.fetch(descriptor)) ?? []).compactMap { entry in
            guard let position = try? JSONDecoder().decode(Position.self, from: entry.payload) else { return nil }
            return WaitingPosition(bookID: entry.bookID, position: position)
        }
    }

    /// Removes `position` from the Outbox, accepted or refused for good, unless newer reading
    /// replaced it while it was in flight.
    func removeFromOutbox(_ position: Position) throws {
        guard let entry = entry(position.bookFileID), entry.recordedAt == position.recordedAt else { return }
        modelContext.delete(entry)
        try modelContext.save()
    }

    /// Drops the Stale entry `stale` and takes the Server's `newer` Position as the latest,
    /// unless reading on this device since then is newer still.
    func adopt(_ newer: Position, replacing stale: Position) throws {
        if let entry = entry(stale.bookFileID), entry.recordedAt == stale.recordedAt {
            modelContext.delete(entry)
        }
        let local = position(bookFileID: newer.bookFileID)
        if local.map({ $0.recordedAt < newer.recordedAt }) ?? true {
            let payload = try JSONEncoder().encode(newer)
            if let stored = stored(newer.bookFileID) {
                stored.payload = payload
            } else {
                modelContext.insert(StoredPosition(bookFileID: newer.bookFileID, payload: payload))
            }
        }
        try modelContext.save()
    }

    func clear() throws {
        try modelContext.delete(model: StoredPosition.self)
        try modelContext.delete(model: OutboxEntry.self)
        try modelContext.save()
    }

    private func stored(_ bookFileID: Int) -> StoredPosition? {
        var descriptor = FetchDescriptor<StoredPosition>(predicate: #Predicate { $0.bookFileID == bookFileID })
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func entry(_ bookFileID: Int) -> OutboxEntry? {
        var descriptor = FetchDescriptor<OutboxEntry>(predicate: #Predicate { $0.bookFileID == bookFileID })
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }
}
