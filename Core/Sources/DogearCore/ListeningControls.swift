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

/// The listener's choices for every audiobook: how far the skip keys jump and the playback speed.
public struct ListeningSettings: Sendable, Equatable {
    public static let skipChoices: [Duration] = [10, 15, 30, 45, 60].map { .seconds($0) }
    public static let speeds: [Float] = [0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3]
    public static let standard = ListeningSettings(skipBack: .seconds(15), skipForward: .seconds(30), speed: 1)

    public var skipBack: Duration
    public var skipForward: Duration
    public var speed: Float

    public init(skipBack: Duration, skipForward: Duration, speed: Float) {
        self.skipBack = skipBack
        self.skipForward = skipForward
        self.speed = speed
    }

    /// From what the device saved, in whole seconds and a rate. A value that isn't one of the
    /// choices (never saved, or from an older Dogear) falls back to the standard one.
    public init(storedSkipBack: Int?, storedSkipForward: Int?, storedSpeed: Float?) {
        func skip(_ seconds: Int?, or standard: Duration) -> Duration {
            guard let seconds else { return standard }
            return Self.skipChoices.first { $0 == .seconds(seconds) } ?? standard
        }
        self.init(
            skipBack: skip(storedSkipBack, or: Self.standard.skipBack),
            skipForward: skip(storedSkipForward, or: Self.standard.skipForward),
            speed: storedSpeed.flatMap { speed in Self.speeds.first { $0 == speed } } ?? Self.standard.speed
        )
    }
}
