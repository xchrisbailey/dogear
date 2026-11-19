import Foundation

/// Stops playback after a stretch of listening or at the end of the Chapter playing.
///
/// Times are whole-book times, so the player maps them to and from Tracks.
public struct SleepTimer: Sendable, Equatable {
    public enum Mode: Sendable, Equatable {
        case after(Duration)
        case endOfChapter
    }

    public let mode: Mode
    /// Listening time left for `.after`; nil for `.endOfChapter`.
    public private(set) var remaining: Duration?
    private var stopsAt: Duration?

    public init(_ mode: Mode, at time: Duration, in info: AudiobookInfo) {
        self.mode = mode
        switch mode {
        case let .after(duration): remaining = duration
        case .endOfChapter: stopsAt = info.chapterEnd(at: time)
        }
    }

    /// Playback ran on for `elapsed` and is now at `time`. True when it should stop.
    public mutating func played(_ elapsed: Duration, to time: Duration) -> Bool {
        if let remaining {
            self.remaining = max(.zero, remaining - elapsed)
            return self.remaining == .zero
        }
        if let stopsAt { return time >= stopsAt }
        return false
    }

    /// The listener skipped or jumped to `time`: "end of Chapter" now means the Chapter there.
    public mutating func moved(to time: Duration, in info: AudiobookInfo) {
        if mode == .endOfChapter { stopsAt = info.chapterEnd(at: time) }
    }
}

extension AudiobookInfo {
    /// Where skipping `interval` from `time` lands (back when negative), within the Book file.
    public func skip(from time: Duration, by interval: Duration) -> Duration {
        min(max(.zero, time + interval), duration)
    }

    /// Where the Chapter playing at `time` ends. Folder audiobooks have no Chapters from the
    /// Server, so their Tracks stand in.
    public func chapterEnd(at time: Duration) -> Duration {
        let starts = chapters.isEmpty ? tracks.map(\.start) : chapters.map(\.start)
        return starts.first { $0 > time } ?? duration
    }
}
