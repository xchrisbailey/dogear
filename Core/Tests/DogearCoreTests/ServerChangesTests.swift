import DogearCore
import Foundation
import Testing

/// When Grimmory changes underneath Dogear or can't be reached, the app keeps working from what
/// it has on the device, and nothing in the Outbox is lost.
struct ServerChangesTests {
    let server = FakeGrimmory()
    let tokenStore = InMemoryTokenStore()
    let clock = TestClock(Date(timeIntervalSince1970: 1_700_000_000))
    let directory = FileManager.default.temporaryDirectory.appending(path: "dogear-server-changes-\(UUID().uuidString)")

    func signedIn() async throws -> Account {
        let account = Account(urlSession: server.session, tokenStore: tokenStore, clock: clock)
        _ = try await account.signIn(address: FakeGrimmory.address, username: "reader", password: "correct horse")
        return account
    }

    func positions() throws -> Positions {
        Positions(store: try PositionStore(url: directory.appending(path: "Positions.store")), clock: clock)
    }

    func library(_ account: Account) throws -> Library {
        Library(account: account, store: try LibraryStore(url: directory.appending(path: "Library.store")))
    }

    func epub(_ throughBook: Double) -> Position.Location {
        .epub(EPUBLocation(href: "OEBPS/ch03.xhtml", throughChapter: 0.5, throughBook: throughBook, cfi: "epubcfi(/6/8!/4/2/1:0)"))
    }

    @Test func pushAnsweredByAWebPageStaysInTheOutbox() async throws {
        let shared = SharedPositions(account: try await signedIn())
        let reading = try positions()
        try await reading.record(epub(0.21), bookFileID: 4, bookID: 4)
        // A Grimmory that moved the endpoint answers with its web app, still 200.
        server.answer("PUT", "/api/v1/app/books/4/progress", with: FakeGrimmory.spaPage)

        await #expect(throws: RequestError.serverChanged) { try await reading.flushOutbox(to: shared) }

        #expect(await try positions().outboxCount() == 1)
    }

    @Test func responseInANewShapeKeepsTheCachedBooksAndSaysUpdateDogear() async throws {
        server.shelve([FakeGrimmory.mobyDick, FakeGrimmory.atomicHabits])
        let account = try await signedIn()
        let cached = try await library(account).refresh()
        server.answer("GET", "/api/v1/app/books", with: .response(status: 200, body: Data(#"{"items":[],"next":null}"#.utf8)))

        let changed = try library(account)
        await #expect(throws: RequestError.serverChanged) { try await changed.refresh() }

        #expect(await changed.cachedBooks() == cached)
        #expect(await account.serverStatus == ServerStatus(isReachable: true, hasChanged: true))
        #expect(RequestError.serverChanged.errorDescription == "The Server's responses have changed shape. Update Dogear.")
    }

    @Test func refusedOrMissingIsNotAChangedServer() async throws {
        server.shelve([FakeGrimmory.flatland])
        let account = try await signedIn()

        let gone = try #require(await ServerPDF(account: account, bookID: 999))
        await #expect(throws: RequestError.notFound) { try await gone.contents() }
        // A Book outside the reader's assigned libraries.
        server.answer("GET", "/api/v1/app/books", with: FakeGrimmory.fixture("error-403", status: 403))
        await #expect(throws: RequestError.forbidden) { try await library(account).refresh() }

        #expect(await account.serverStatus == ServerStatus())
        #expect(RequestError.notFound.errorDescription == "This Book or Book file is no longer on your Server.")
    }

    @Test func serverErrorIsOfflineRatherThanAChangedServer() async throws {
        let account = try await signedIn()
        server.answer("GET", "/api/v1/libraries", with: .response(status: 500, body: Data(#"{"status":500}"#.utf8)))

        await #expect(throws: RequestError.unreachable) { try await library(account).refresh() }

        #expect(await account.serverStatus == ServerStatus(isReachable: false, hasChanged: false))
    }

    @Test func serverDownBehindItsProxyIsOfflineAndTheOutboxFlushesOnceItsBack() async throws {
        let account = try await signedIn()
        let reading = try positions()
        try await reading.record(epub(0.21), bookFileID: 4, bookID: 4)
        // Tailscale Serve still answers while Grimmory behind it is down.
        let badGateway = FakeServer.Reply.response(status: 502, body: Data(), contentType: "text/plain")
        server.answer("GET", "/api", with: badGateway)
        server.answer("PUT", "/api", with: badGateway)

        await #expect(throws: RequestError.unreachable) { try await reading.flushOutbox(to: SharedPositions(account: account)) }
        #expect(await account.serverStatus == ServerStatus(isReachable: false, hasChanged: false))
        #expect(await reading.outboxCount() == 1)

        server.clearAnswers()
        #expect(await account.checkServer() == ServerStatus(isReachable: true, hasChanged: false))
        try await reading.flushOutbox(to: SharedPositions(account: account))

        #expect(await reading.outboxCount() == 0)
    }

    @Test func refreshFailingOnTheServerIsOfflineRatherThanAChangedServer() async throws {
        let account = try await signedIn()
        server.expireAccessTokens()
        // Grimmory v3.5.1 answered auth requests with a 500 and an ErrorResponse body.
        server.answer("POST", "/api/v1/auth/refresh", with: .response(status: 500, body: Data(#"{"status":500,"message":"Internal error"}"#.utf8)))

        await #expect(throws: RequestError.unreachable) { try await library(account).refresh() }

        #expect(await account.serverStatus == ServerStatus(isReachable: false, hasChanged: false))
        #expect(await account.session?.needsSignIn == false)
    }

    @Test func expiredAccessTokenOffTheTailnetKeepsTheSignInForLater() async throws {
        let account = try await signedIn()
        let reading = try positions()
        try await reading.record(epub(0.21), bookFileID: 4, bookID: 4)
        server.expireAccessTokens()
        server.answer("POST", "/api/v1/auth/refresh", with: .response(status: 504, body: Data(), contentType: "text/plain"))

        await #expect(throws: RequestError.unreachable) { try await reading.flushOutbox(to: SharedPositions(account: account)) }

        #expect(await account.serverStatus == ServerStatus(isReachable: false, hasChanged: false))
        #expect(await account.session?.needsSignIn == false)
        server.clearAnswers()
        try await reading.flushOutbox(to: SharedPositions(account: account))
        #expect(await reading.outboxCount() == 0)
    }
}
