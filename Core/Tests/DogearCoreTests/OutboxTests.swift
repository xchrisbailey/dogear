import DogearCore
import Foundation
import Testing

/// Positions recorded on the device wait in the Outbox until the Server accepts them,
/// and never overwrite newer reading done elsewhere (ADR 0002).
struct OutboxTests {
    let server = FakeGrimmory()
    let tokenStore = InMemoryTokenStore()
    /// Nov 2023: earlier than the Shared positions in the fixtures (Nov 2026).
    let clock = TestClock(Date(timeIntervalSince1970: 1_700_000_000))
    let storeURL = FileManager.default.temporaryDirectory
        .appending(path: "dogear-outbox-\(UUID().uuidString)")
        .appending(path: "Positions.store")

    /// Positions over the store on disk; a second call simulates a relaunch.
    func positions() throws -> Positions {
        Positions(store: try PositionStore(url: storeURL), clock: clock)
    }

    func signedIn() async throws -> SharedPositions {
        let account = Account(urlSession: server.session, tokenStore: tokenStore, clock: clock)
        _ = try await account.signIn(address: FakeGrimmory.address, username: "reader", password: "correct horse")
        return SharedPositions(account: account)
    }

    func epub(_ href: String, _ bookProgress: Double) -> Position.Location {
        .epub(EPUBLocation(href: href, chapterProgress: 0.5, bookProgress: bookProgress, cfi: "epubcfi(/6/8!/4/2/1:0)"))
    }

    var pushes: [FakeGrimmory.Request] {
        server.requests.filter { $0.method == "PUT" }
    }

    func pushed(_ request: FakeGrimmory.Request) -> (path: String, bookFileID: Int?, percent: Double?) {
        let fileProgress = request.json?["fileProgress"] as? [String: any Sendable]
        return (request.path, fileProgress?["bookFileId"] as? Int, fileProgress?["progressPercent"] as? Double)
    }

    @Test func recordedPositionWaitsAcrossARelaunchUntilFlushed() async throws {
        let shared = try await signedIn()
        try await positions().record(epub("OEBPS/ch03.xhtml", 0.21), bookFileID: 4, bookID: 4)

        let relaunched = try positions()
        #expect(await relaunched.outboxCount() == 1)
        #expect(await relaunched.latest(bookFileID: 4)?.location == epub("OEBPS/ch03.xhtml", 0.21))

        try await relaunched.flushOutbox(to: shared)

        #expect(pushes.map(pushed).map(\.path) == ["/api/v1/app/books/4/progress"])
        #expect(pushes.map(pushed).map(\.percent) == [21])
        #expect(await relaunched.outboxCount() == 0)
        #expect(await try positions().outboxCount() == 0)
    }

    @Test func staleEntryIsDroppedAndTheSharedPositionAdopted() async throws {
        let shared = try await signedIn()
        // The web reader saved at 2026-11-19T15:34:09Z, after this offline reading in 2023.
        server.holdSharedPosition(bookID: 4, fixture: "app-progress-epub")
        let reading = try positions()
        try await reading.record(epub("OEBPS/ch03.xhtml", 0.9), bookFileID: 4, bookID: 4)

        try await reading.flushOutbox(to: shared)

        #expect(pushes.isEmpty)
        #expect(await reading.outboxCount() == 0)
        let adopted = try #require(await try positions().latest(bookFileID: 4))
        #expect(adopted.recordedAt == ISO8601DateFormatter().date(from: "2026-11-19T15:34:09Z"))
        guard case let .epub(location) = adopted.location else { Issue.record("not an EPUB Position"); return }
        #expect(location.cfi == "epubcfi(/6/30!/4[x9780735211308_EPUB-13],/2/34,/6/10/3:74)")
        #expect(location.bookProgress == 0.281341)
    }

    @Test func newestReadingWinsEvenWhenBehindTheSharedPosition() async throws {
        let shared = try await signedIn()
        server.holdSharedPosition(bookID: 4, fixture: "app-progress-epub")
        clock.advance(by: 100_000_000) // 2027: after the web reader's save.
        let reading = try positions()
        try await reading.record(epub("OEBPS/ch02.xhtml", 0.05), bookFileID: 4, bookID: 4)

        try await reading.flushOutbox(to: shared)

        #expect(pushes.map(pushed).map(\.percent) == [5])
        #expect(await reading.outboxCount() == 0)
        guard case let .epub(location)? = await reading.latest(bookFileID: 4)?.location else {
            Issue.record("no EPUB Position"); return
        }
        #expect(location.bookProgress == 0.05)
    }

    @Test func readingInAnotherFormatDoesNotMakeAnEntryStale() async throws {
        let shared = try await signedIn()
        // Listening to the audiobook moved the Book's lastReadTime past this EPUB reading.
        server.holdSharedPosition(bookID: 4, fixture: "derived-app-progress-audiobook")
        let reading = try positions()
        try await reading.record(epub("OEBPS/ch03.xhtml", 0.3), bookFileID: 4, bookID: 4)

        try await reading.flushOutbox(to: shared)

        #expect(pushes.map(pushed).map(\.percent) == [30])
    }

    @Test func outboxOutlivesAnExpiredSignInAndFlushesAfterSigningInAgain() async throws {
        let shared = try await signedIn()
        server.expireAccessTokens()
        server.revokeRefreshTokens()
        let reading = try positions()
        try await reading.record(epub("OEBPS/ch03.xhtml", 0.21), bookFileID: 4, bookID: 4)

        await #expect(throws: RequestError.needsSignIn) { try await reading.flushOutbox(to: shared) }
        #expect(pushes.isEmpty)

        let relaunched = try positions()
        let account = Account(urlSession: server.session, tokenStore: tokenStore, clock: clock)
        _ = try await account.signIn(address: FakeGrimmory.address, username: "reader", password: "correct horse")
        #expect(await relaunched.outboxCount() == 1)

        try await relaunched.flushOutbox(to: SharedPositions(account: account))

        #expect(pushes.map(pushed).map(\.percent) == [21])
        #expect(await relaunched.outboxCount() == 0)
    }

    @Test func entriesTheServerCanNeverAcceptAreDroppedWithoutHoldingUpTheRest() async throws {
        let shared = try await signedIn()
        let reading = try positions()
        try await reading.record(epub("OEBPS/ch01.xhtml", 0.01), bookFileID: 31, bookID: 7)
        clock.advance(by: 60)
        try await reading.record(epub("OEBPS/ch01.xhtml", 0.02), bookFileID: 90, bookID: 9)
        clock.advance(by: 60)
        try await reading.record(epub("OEBPS/ch02.xhtml", 0.03), bookFileID: 4, bookID: 4)
        // Book 7 was deleted on the Server; Book 9 moved to a library the reader can't see.
        server.answer("GET", "/api/v1/app/books/7/progress", with: FakeGrimmory.fixture("error-404-book", status: 404))
        server.answer("PUT", "/api/v1/app/books/9/progress", with: FakeGrimmory.fixture("error-403", status: 403))

        try await reading.flushOutbox(to: shared)

        #expect(pushes.map(pushed).filter { $0.path.contains("/4/") }.map(\.percent) == [3])
        #expect(await reading.outboxCount() == 0)
        #expect(await reading.latest(bookFileID: 31) != nil)
    }

    @Test func unreachableServerLeavesTheOutboxForLater() async throws {
        let shared = try await signedIn()
        let reading = try positions()
        try await reading.record(epub("OEBPS/ch03.xhtml", 0.21), bookFileID: 4, bookID: 4)
        server.setKind(.unreachable)

        await #expect(throws: RequestError.unreachable) { try await reading.flushOutbox(to: shared) }

        #expect(await reading.outboxCount() == 1)
        server.setKind(.grimmory)
        try await reading.flushOutbox(to: shared)
        #expect(await reading.outboxCount() == 0)
    }

    @Test func flushPushesTheNewestPositionPerBookFileInTheOrderTheReadingHappened() async throws {
        let shared = try await signedIn()
        let reading = try positions()
        try await reading.record(epub("OEBPS/ch01.xhtml", 0.01), bookFileID: 31, bookID: 7)
        clock.advance(by: 60)
        try await reading.record(epub("OEBPS/ch01.xhtml", 0.02), bookFileID: 4, bookID: 4)
        clock.advance(by: 60)
        try await reading.record(epub("OEBPS/ch02.xhtml", 0.03), bookFileID: 4, bookID: 4)
        clock.advance(by: 60)
        try await reading.record(epub("OEBPS/ch01.xhtml", 0.04), bookFileID: 32, bookID: 7)
        #expect(await reading.outboxCount() == 3)

        try await reading.flushOutbox(to: shared)

        #expect(pushes.map(pushed).map(\.bookFileID) == [31, 4, 32])
        #expect(pushes.map(pushed).map(\.percent) == [1, 3, 4])
        // Each Book's Shared position is checked once, before its first push moves `lastReadTime`.
        let checks = server.requests.filter { $0.method == "GET" && $0.path.hasSuffix("/progress") }
        #expect(checks.map(\.path) == ["/api/v1/app/books/7/progress", "/api/v1/app/books/4/progress"])
    }
}
