import DogearCore
import Foundation
import Testing

/// An open reader or player keeps to where the reader is: it records only their own moves, and
/// on returning to the app it moves to newer reading done elsewhere (ADR 0002).
struct CatchUpTests {
    let server = FakeGrimmory()
    let tokenStore = InMemoryTokenStore()
    /// Nov 2023: earlier than the Shared position in the fixture (2026-11-19T15:34:09Z).
    let clock = TestClock(Date(timeIntervalSince1970: 1_700_000_000))
    let storeURL = FileManager.default.temporaryDirectory
        .appending(path: "dogear-catch-up-\(UUID().uuidString)")
        .appending(path: "Positions.store")
    /// The web reader's spot in the `app-progress-epub` fixture.
    static let webCFI = "epubcfi(/6/30!/4[x9780735211308_EPUB-13],/2/34,/6/10/3:74)"

    func positions() throws -> Positions {
        Positions(store: try PositionStore(url: storeURL), clock: clock)
    }

    func signedIn() async throws -> SharedPositions {
        let account = Account(urlSession: server.session, tokenStore: tokenStore, clock: clock)
        _ = try await account.signIn(address: FakeGrimmory.address, username: "reader", password: "correct horse")
        return SharedPositions(account: account)
    }

    func epub(_ href: String, _ throughBook: Double, cfi: String? = "epubcfi(/6/8!/4/2/1:0)") -> Position.Location {
        .epub(EPUBLocation(href: href, throughChapter: 0.5, throughBook: throughBook, cfi: cfi, readerState: "{}"))
    }

    @Test func layoutRelocationsAreNotTheReadersMoves() {
        var moves = ReaderMoves()
        // Opening: the reader hasn't moved yet, wherever the page settles.
        #expect(!moves.isReading)

        moves.readerMoved()
        #expect(moves.isReading)

        // The controls were hidden, so the page was laid out again.
        moves.relocated()
        #expect(!moves.isReading)

        moves.readerMoved()
        #expect(moves.isReading)
    }

    @Test func newerReadingElsewhereIsCaughtUpToAndAdopted() async throws {
        let shared = try await signedIn()
        server.holdSharedPosition(bookID: 4, fixture: "app-progress-epub")
        let reading = try positions()
        // Read here in 2023 and not yet sent; the web reader read on since.
        try await reading.record(epub("OEBPS/ch03.xhtml", 0.9), bookFileID: 4, bookID: 4)

        let newer = try #require(try await reading.catchUp(.epub, bookID: 4, bookFileID: 4, from: shared))

        guard case let .epub(location) = newer.location else { Issue.record("not an EPUB Position"); return }
        #expect(location.cfi == Self.webCFI)
        #expect(location.throughBook == 0.281341)
        #expect(await reading.latest(bookFileID: 4) == newer)
        // The entry is Stale now, so it's never pushed over the web reader's reading.
        #expect(await reading.outboxCount() == 0)
        #expect(server.requests.filter { $0.method == "PUT" }.isEmpty)
    }

    @Test func readingHereSinceIsKept() async throws {
        let shared = try await signedIn()
        server.holdSharedPosition(bookID: 4, fixture: "app-progress-epub")
        clock.advance(by: 100_000_000) // 2027: after the web reader's save.
        let reading = try positions()
        let mine = try await reading.record(epub("OEBPS/ch02.xhtml", 0.05), bookFileID: 4, bookID: 4)

        #expect(try await reading.catchUp(.epub, bookID: 4, bookFileID: 4, from: shared) == nil)
        #expect(await reading.latest(bookFileID: 4) == mine)
    }

    @Test func sharedPositionThisDeviceSentIsNotCaughtUpTo() async throws {
        let shared = try await signedIn()
        // The Server stamps what it's sent with its own, later, time.
        server.holdSharedPosition(bookID: 4, fixture: "app-progress-epub")
        let reading = try positions()
        let mine = try await reading.record(
            epub("OEBPS/xhtml/15_7_The_Secret_to_Self-.xhtml", 0.281341, cfi: Self.webCFI), bookFileID: 4, bookID: 4
        )

        #expect(try await reading.catchUp(.epub, bookID: 4, bookFileID: 4, from: shared) == nil)
        #expect(await reading.latest(bookFileID: 4) == mine)
    }
}
