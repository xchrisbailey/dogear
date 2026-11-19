import DogearCore
import Foundation
import Testing

/// Listening to a single-file audiobook: its Position is Track 0 plus milliseconds, shared with
/// Grimmory's web player, and its stream keeps working as the access token is refreshed.
struct ListenAudiobookTests {
    let server = FakeGrimmory()
    let tokenStore = InMemoryTokenStore()

    func signedIn() async throws -> Account {
        server.shelve([FakeGrimmory.projectHailMary])
        let account = Account(urlSession: server.session, tokenStore: tokenStore)
        _ = try await account.signIn(address: FakeGrimmory.address, username: "reader", password: "correct horse")
        return account
    }

    @Test func positionIsPushedAsTrackZeroAndMillisecondsAsFileProgressOnly() async throws {
        let shared = SharedPositions(account: try await signedIn())
        let position = Position(
            bookFileID: 5,
            location: .audiobook(AudiobookLocation(trackIndex: 0, milliseconds: 41_369_321, bookProgress: 41_369_321 / 58_253_000)),
            recordedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        try await shared.push(position, bookID: 5)

        // The request body Grimmory's source says the web player's save amounts to.
        let sent = try #require(server.requests.last)
        #expect(sent.method == "PUT")
        #expect(sent.path == "/api/v1/app/books/5/progress")
        #expect(sent.json?.keys.sorted() == ["fileProgress"])
        let fileProgress = try #require(sent.json?["fileProgress"] as? [String: any Sendable])
        #expect(fileProgress.keys.sorted() == ["bookFileId", "positionData", "positionHref", "progressPercent"])
        #expect(fileProgress["bookFileId"] as? Int == 5)
        #expect(fileProgress["positionData"] as? String == "41369321")
        #expect(fileProgress["positionHref"] as? String == "0")
        #expect(fileProgress["progressPercent"] as? Double == 71.0)
    }

    @Test func webPlayersPositionComesBackAsTrackZeroAndMilliseconds() async throws {
        let shared = SharedPositions(account: try await signedIn())
        // The web player leaves out the Track for single-file audiobooks.
        server.holdSharedPosition(bookID: 5, fixture: "derived-app-progress-audiobook-single")

        let position = try #require(try await shared.latest(.audiobook, bookID: 5, bookFileID: 5))

        #expect(position.bookFileID == 5)
        #expect(position.recordedAt == ISO8601DateFormatter().date(from: "2026-11-19T15:40:00Z"))
        #expect(position.location == .audiobook(AudiobookLocation(trackIndex: 0, milliseconds: 41_369_321, bookProgress: 0.71)))
    }

    /// Fetches `url` as AVPlayer does: no Authorization header, the token rides in the query.
    func status(of url: URL) async throws -> Int {
        let (_, response) = try await server.session.data(from: url)
        return (response as? HTTPURLResponse)?.statusCode ?? 0
    }

    @Test func chaptersAreListedFromZeroAndTheWholeBookStreamCarriesTheToken() async throws {
        let audiobook = try #require(await ServerAudiobook(account: try await signedIn(), bookID: 5))

        let info = try await audiobook.info()
        var streams = await audiobook.streamUpdates().makeAsyncIterator()
        let stream = try #require(await streams.next())

        #expect(info.bookFileID == 5)
        #expect(info.title == "Project Hail Mary")
        #expect(info.duration == .milliseconds(58_253_000))
        #expect(info.chapters.map(\.index) == [0, 1, 2, 29])
        #expect(info.chapters.map(\.title) == ["001", "002", "003", "030"])
        #expect(info.chapters.map(\.start) == [.zero, .milliseconds(2_224_936), .milliseconds(3_946_417), .milliseconds(57_371_538)])
        #expect(info.chapter(at: .milliseconds(3_000_000))?.index == 1)

        let query = URLComponents(url: stream.wholeBook, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(stream.wholeBook.path == "/api/v1/audiobooks/5/stream")
        #expect(query.contains(URLQueryItem(name: "token", value: "access-1")))
        #expect(try await status(of: stream.wholeBook) == 200)
    }

    @Test func refreshedTokenGivesNewStreamURLsToRebuildFrom() async throws {
        let account = try await signedIn()
        let audiobook = try #require(await ServerAudiobook(account: account, bookID: 5))
        var streams = await audiobook.streamUpdates().makeAsyncIterator()
        let before = try #require(await streams.next())
        server.expireAccessTokens()

        // Saving the Position every few seconds is what notices the expired token while listening.
        let position = Position(
            bookFileID: 5, location: .audiobook(AudiobookLocation(trackIndex: 0, milliseconds: 7_200_000, bookProgress: 0.12)),
            recordedAt: Date()
        )
        try await SharedPositions(account: account).push(position, bookID: 5)
        let after = try #require(await streams.next())

        #expect(try await status(of: before.wholeBook) == 401)
        #expect(try await status(of: after.wholeBook) == 200)
        #expect(after.wholeBook.path == "/api/v1/audiobooks/5/stream")
    }

    @Test func rejectedStreamIsReauthorizedWithOneRefresh() async throws {
        let audiobook = try #require(await ServerAudiobook(account: try await signedIn(), bookID: 5))
        var streams = await audiobook.streamUpdates().makeAsyncIterator()
        let rejected = try #require(await streams.next())
        server.expireAccessTokens()
        #expect(try await status(of: rejected.wholeBook) == 401)

        // The player's item failure and a Position save can both notice at once.
        async let first = audiobook.reauthorize(afterRejecting: rejected)
        async let second = audiobook.reauthorize(afterRejecting: rejected)
        let (a, b) = try await (first, second)

        #expect(a == b)
        #expect(try await status(of: a.wholeBook) == 200)
        #expect(server.requests.filter { $0.path == "/api/v1/auth/refresh" }.count == 1)
        #expect(await streams.next() == a)
    }
}
