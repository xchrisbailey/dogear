import Foundation

/// A Book's audiobook as the Server streams it, so it plays without a Download.
///
/// AVPlayer can't add headers, so stream URLs carry the access token as a `token` query parameter
/// and each player item is stuck with the token it was built with. When the token changes the
/// player rebuilds its items from the new URLs and seeks back to the same second.
public struct ServerAudiobook: AudiobookSource {
    private let account: Account
    private let server: URL

    public let bookID: Int

    /// nil when signed out.
    public init?(account: Account, bookID: Int) async {
        guard let server = await account.session?.server else { return nil }
        self.account = account
        self.server = server
        self.bookID = bookID
    }

    /// Duration, Chapters and Tracks. `bookFileID` is the Book file Positions are recorded against.
    public func info() async throws(RequestError) -> AudiobookInfo {
        var url = server.appending(path: "api/v1/audiobooks/\(bookID)/info")
        url.append(queryItems: [Self.bookType])
        return try await account.fetch(AudiobookInfo.self, URLRequest(url: url))
    }

    /// The stream URLs now, then new ones each time the access token changes (a refresh, or
    /// signing in again). Each one means: rebuild the player items and seek back.
    public func streamUpdates() async -> AsyncStream<AudiobookStream> {
        let sessions = await account.sessionUpdates()
        return AsyncStream { continuation in
            let task = Task {
                var lastToken: String?
                for await session in sessions {
                    guard let token = session?.accessToken, token != lastToken else { continue }
                    lastToken = token
                    continuation.yield(stream(token: token))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// New stream URLs after the Server refused `rejected`, refreshing the tokens if no other
    /// request already has. A refused token makes the player fail silently, so the player
    /// asks here before showing an error.
    public func reauthorize(afterRejecting rejected: AudiobookStream) async throws(RequestError) -> AudiobookStream {
        stream(token: try await account.accessToken(replacing: rejected.accessToken))
    }

    private func stream(token: String) -> AudiobookStream {
        AudiobookStream(base: server.appending(path: "api/v1/audiobooks/\(bookID)"), accessToken: token)
    }

    /// Picks the audiobook in case the Book's primary file is another format.
    fileprivate static let bookType = URLQueryItem(name: "bookType", value: "AUDIOBOOK")
}

/// Where a player gets an audiobook from: streamed from the Server, or a Download.
public protocol AudiobookSource: Sendable {
    var bookID: Int { get }
    /// Duration, Chapters and Tracks. `bookFileID` is the Book file Positions are recorded against.
    func info() async throws(RequestError) -> AudiobookInfo
    /// The URLs to play now, then new ones whenever the old ones stop working.
    func streamUpdates() async -> AsyncStream<AudiobookStream>
    /// New URLs after playing `rejected` failed, or an error when there's nothing to try.
    func reauthorize(afterRejecting rejected: AudiobookStream) async throws(RequestError) -> AudiobookStream
}

/// The URLs an audiobook plays from: Server streams signed with one access token, or files on the device.
public struct AudiobookStream: Sendable, Equatable {
    private enum Source: Equatable {
        case server(base: URL, accessToken: String)
        case device(wholeBook: URL, tracks: [Int: URL])
    }

    private let source: Source

    fileprivate init(base: URL, accessToken: String) {
        source = .server(base: base, accessToken: accessToken)
    }

    init(wholeBook: URL, tracks: [Int: URL]) {
        source = .device(wholeBook: wholeBook, tracks: tracks)
    }

    var accessToken: String {
        if case let .server(_, accessToken) = source { accessToken } else { "" }
    }

    /// The whole Book file, for single-file audiobooks.
    public var wholeBook: URL {
        switch source {
        case let .server(base, accessToken): Self.signed(base.appending(path: "stream"), accessToken)
        case let .device(wholeBook, _): wholeBook
        }
    }

    /// One Track of a folder audiobook.
    public func track(_ index: Int) -> URL {
        switch source {
        case let .server(base, accessToken): Self.signed(base.appending(path: "track/\(index)/stream"), accessToken)
        case let .device(wholeBook, tracks): tracks[index] ?? wholeBook
        }
    }

    private static func signed(_ url: URL, _ accessToken: String) -> URL {
        url.appending(queryItems: [ServerAudiobook.bookType, URLQueryItem(name: "token", value: accessToken)])
    }
}

public struct AudiobookInfo: Decodable, Sendable, Equatable {
    public struct Chapter: Sendable, Equatable, Identifiable {
        /// 0-based, as the Server and web player number them.
        public var index: Int
        public var title: String
        public var start: Duration

        public var id: Int { index }
    }

    /// One file of a folder audiobook.
    public struct Track: Sendable, Equatable, Identifiable {
        public var index: Int
        public var title: String?
        public var duration: Duration
        /// Where the Track starts in the whole Book file.
        public var start: Duration

        public var id: Int { index }
    }

    public var bookFileID: Int
    public var title: String?
    public var author: String?
    public var duration: Duration
    /// True when the audiobook is a folder of Tracks rather than one file.
    public var isFolder: Bool
    /// Empty for folder audiobooks, which the Server doesn't read Chapters from.
    public var chapters: [Chapter]
    /// Empty for single-file audiobooks.
    public var tracks: [Track]

    /// The Chapter playing at `time` into the whole Book file.
    public func chapter(at time: Duration) -> Chapter? {
        chapters.last { $0.start <= time } ?? chapters.first
    }

    /// The Track playing at `time` into the whole Book file; nil for single-file audiobooks.
    public func track(at time: Duration) -> Track? {
        tracks.last { $0.start <= time } ?? tracks.first
    }

    /// The Position for `time` into the whole Book file: the Track and the milliseconds into it.
    /// Single-file audiobooks are Track 0.
    public func location(at time: Duration) -> AudiobookLocation {
        let track = track(at: time)
        let offset = time - (track?.start ?? .zero)
        return AudiobookLocation(
            trackIndex: track?.index ?? 0,
            milliseconds: Int(offset / .milliseconds(1)),
            throughBook: duration > .zero ? min(1, max(0, time / duration)) : 0
        )
    }

    /// Where `location` is in the whole Book file. Single-file audiobooks ignore the Track.
    public func time(of location: AudiobookLocation) -> Duration {
        let offset = Duration.milliseconds(location.milliseconds)
        guard !tracks.isEmpty else { return min(offset, duration) }
        // A Position recorded against Tracks the Server no longer lists (files changed on disk)
        // resumes at the end rather than somewhere unrelated.
        guard let track = tracks.first(where: { $0.index == location.trackIndex }) else { return duration }
        return track.start + min(offset, track.duration)
    }

    private struct Payload: Decodable {
        struct Chapter: Decodable {
            var index: Int
            var title: String?
            var startTimeMs: Int
        }

        struct Track: Decodable {
            var index: Int
            var title: String?
            var durationMs: Int
            var cumulativeStartMs: Int
        }

        var bookFileId: Int
        var title: String?
        var author: String?
        var durationMs: Int
        var folderBased: Bool?
        var chapters: [Chapter]?
        var tracks: [Track]?
    }

    public init(from decoder: any Decoder) throws {
        let payload = try Payload(from: decoder)
        bookFileID = payload.bookFileId
        title = payload.title
        author = payload.author
        duration = .milliseconds(payload.durationMs)
        isFolder = payload.folderBased ?? false
        chapters = (payload.chapters ?? []).map {
            Chapter(index: $0.index, title: $0.title ?? "Chapter \($0.index + 1)", start: .milliseconds($0.startTimeMs))
        }
        tracks = (payload.tracks ?? []).map {
            Track(index: $0.index, title: $0.title, duration: .milliseconds($0.durationMs), start: .milliseconds($0.cumulativeStartMs))
        }
    }
}
