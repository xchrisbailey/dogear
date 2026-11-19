import Foundation

/// Which URLs the player queues for an audiobook and where it seeks, so the rules are decided
/// here and the player only carries them out.
///
/// Server stream URLs carry the access token, and a player item is stuck with the URL it was built
/// with. So whenever the token changes the items are rebuilt from the new URLs and seeked back to
/// the same second; otherwise playback would stop when the 2-hour token expires.
public struct AudiobookQueue: Sendable {
    public struct Item: Sendable, Equatable {
        public var url: URL
        /// Where the item starts in the whole Book file.
        public var start: Duration
    }

    /// Items to replace the player's queue with, and where to seek in the first one.
    public struct Plan: Sendable, Equatable {
        public var items: [Item]
        public var seek: Duration
    }

    public let info: AudiobookInfo
    /// The URLs the player's items were built from.
    public private(set) var stream: AudiobookStream?

    public init(info: AudiobookInfo) {
        self.info = info
    }

    /// New URLs arrived (the token changed, or a fresh one after the player failed). Returns what
    /// to queue to carry on at `time`, or nil when the player's items already use these URLs and
    /// still work.
    public mutating func streamChanged(to stream: AudiobookStream, at time: Duration, hasWorkingItems: Bool) -> Plan? {
        if stream == self.stream, hasWorkingItems { return nil }
        self.stream = stream
        return plan(at: time)
    }

    /// What to queue to play from `time` with the current URLs, such as after a seek to another Track.
    public func plan(at time: Duration) -> Plan? {
        guard let stream else { return nil }
        // A folder queues the playing Track onwards, so the next one is preloaded and starts without a gap.
        guard let playing = info.track(at: time) else {
            return Plan(items: [Item(url: stream.wholeBook, start: .zero)], seek: time)
        }
        let items = info.tracks.filter { $0.index >= playing.index }.map { Item(url: stream.track($0.index), start: $0.start) }
        return Plan(items: items, seek: time - playing.start)
    }

    /// Whether moving from `from` to `to` leaves the playing item, so the queue must be rebuilt.
    public func leavesTheItem(from: Duration, to: Duration) -> Bool {
        info.track(at: from) != info.track(at: to)
    }
}
