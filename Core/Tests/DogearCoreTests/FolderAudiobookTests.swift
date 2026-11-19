import DogearCore
import Foundation
import Testing

/// Listening to a folder audiobook: Tracks play in order from their own streams, and the Position
/// is the Track index plus milliseconds within it, mapped to and from whole-book time.
struct FolderAudiobookTests {
    let server = FakeGrimmory()

    func signedIn() async throws -> Account {
        server.shelve([FakeGrimmory.slaughterhouseFive])
        let account = Account(urlSession: server.session, tokenStore: InMemoryTokenStore())
        _ = try await account.signIn(address: FakeGrimmory.address, username: "reader", password: "correct horse")
        return account
    }

    func audiobook() async throws -> ServerAudiobook {
        try #require(await ServerAudiobook(account: try await signedIn(), bookID: 6))
    }

    @Test func wholeBookTimeMapsToTheTrackAndMillisecondsWithinIt() async throws {
        let info = try await audiobook().info()

        #expect(info.isFolder)
        #expect(info.tracks.map(\.index) == [0, 1, 2, 80])
        // 400 s in is 79.635 s into Track 1, which starts at 320.365 s.
        let location = info.location(at: .milliseconds(400_000))
        #expect(location.trackIndex == 1)
        #expect(location.milliseconds == 79_635)
        #expect(abs(location.throughBook - 0.018395) < 0.000001)
        #expect(info.location(at: .milliseconds(21_400_000)).trackIndex == 80)
        #expect(info.location(at: .milliseconds(21_400_000)).milliseconds == 99_640)
        // A Track's first millisecond belongs to it, not the one before.
        #expect(info.location(at: .milliseconds(320_365)).trackIndex == 1)
        #expect(info.location(at: .milliseconds(320_365)).milliseconds == 0)
    }

    @Test func webPlayersPositionResumesOnItsTrackAndSecond() async throws {
        let account = try await signedIn()
        let info = try await #require(await ServerAudiobook(account: account, bookID: 6)).info()
        server.holdSharedPosition(bookID: 6, fixture: "derived-app-progress-audiobook")
        let shared = SharedPositions(account: account)

        let position = try #require(try await shared.latest(.audiobook, bookID: 6, bookFileID: 6))
        guard case let .audiobook(location) = position.location else { Issue.record("not an audiobook"); return }

        // Track 2 starts 740.727 s in; the web player was 60 s into it.
        #expect(info.time(of: location) == .milliseconds(800_727))
        #expect(info.location(at: info.time(of: location)).trackIndex == 2)
        #expect(info.location(at: info.time(of: location)).milliseconds == 60_000)
    }

    @Test func eachTrackStreamsFromItsOwnURLCarryingTheToken() async throws {
        let audiobook = try await audiobook()
        let info = try await audiobook.info()
        var streams = await audiobook.streamUpdates().makeAsyncIterator()
        let stream = try #require(await streams.next())

        let urls = info.tracks.map { stream.track($0.index) }

        #expect(urls.map(\.path) == [0, 1, 2, 80].map { "/api/v1/audiobooks/6/track/\($0)/stream" })
        for url in urls {
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            #expect(query.contains(URLQueryItem(name: "token", value: "access-1")))
            let (_, response) = try await server.session.data(from: url)
            #expect((response as? HTTPURLResponse)?.statusCode == 200)
        }
        let (_, missing) = try await server.session.data(from: stream.track(999))
        #expect((missing as? HTTPURLResponse)?.statusCode == 404)
    }

    @Test func positionIsPushedAsTheTrackIndexAndMillisecondsWithinIt() async throws {
        let account = try await signedIn()
        let info = try await #require(await ServerAudiobook(account: account, bookID: 6)).info()
        let position = Position(bookFileID: 6, location: .audiobook(info.location(at: .milliseconds(800_727))), recordedAt: Date())

        try await SharedPositions(account: account).push(position, bookID: 6)

        // `derived-progress-put-audiobook-folder`: what the web player sends.
        let sent = try #require(server.requests.last)
        let fileProgress = try #require(sent.json?["fileProgress"] as? [String: any Sendable])
        #expect(fileProgress["bookFileId"] as? Int == 6)
        #expect(fileProgress["positionData"] as? String == "60000")
        #expect(fileProgress["positionHref"] as? String == "2")
        #expect(fileProgress["progressPercent"] as? Double == 3.7)
    }

    @Test func positionOnATrackTheServerNoLongerListsResumesAtTheEnd() async throws {
        let info = try await audiobook().info()

        let gone = AudiobookLocation(trackIndex: 999, milliseconds: 5_000, throughBook: 1)

        #expect(info.time(of: gone) == .milliseconds(21_744_676))
    }
}
