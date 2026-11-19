import DogearCore
import Foundation
import Testing

/// PDF Positions shared with Grimmory's web reader: a 1-based page number plus a percentage.
struct ReadPDFTests {
    let server = FakeGrimmory()

    func signedIn() async throws -> Account {
        server.shelve([FakeGrimmory.flatland])
        let account = Account(urlSession: server.session, tokenStore: InMemoryTokenStore())
        _ = try await account.signIn(address: FakeGrimmory.address, username: "reader", password: "correct horse")
        return account
    }

    @Test func pushSendsThePageAsAStringAndThePercentageAsFileProgressOnly() async throws {
        let shared = SharedPositions(account: try await signedIn())
        let position = Position(
            bookFileID: 21,
            location: .pdf(PDFLocation(page: 12, throughBook: 0.048)),
            recordedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        try await shared.push(position, bookID: 9)

        let sent = try #require(server.requests.last)
        #expect(sent.method == "PUT")
        #expect(sent.path == "/api/v1/app/books/9/progress")
        #expect(sent.json?.keys.sorted() == ["fileProgress"])
        let fileProgress = try #require(sent.json?["fileProgress"] as? [String: any Sendable])
        // The Server parses positionData as an integer; anything else is a 400.
        #expect(fileProgress.keys.sorted() == ["bookFileId", "positionData", "progressPercent"])
        #expect(fileProgress["bookFileId"] as? Int == 21)
        #expect(fileProgress["positionData"] as? String == "12")
        #expect(fileProgress["progressPercent"] as? Double == 4.8)
    }

    @Test func webReadersPageComesBack() async throws {
        let shared = SharedPositions(account: try await signedIn())
        server.holdSharedPosition(bookID: 9, fixture: "derived-app-progress-pdf")

        let position = try #require(try await shared.latest(.pdf, bookID: 9, bookFileID: 21))

        #expect(position.bookFileID == 21)
        #expect(position.location == .pdf(PDFLocation(page: 12, throughBook: 0.048)))
        #expect(position.recordedAt == ISO8601DateFormatter().date(from: "2026-11-19T15:41:00Z"))
        // An EPUB Position isn't a page.
        #expect(try await shared.latest(.epub, bookID: 9, bookFileID: 21) == nil)
    }

    @Test func pdfIsFetchedWithTheAccessToken() async throws {
        let account = try await signedIn()
        let pdf = try #require(await ServerPDF(account: account, bookID: 9))
        server.expireAccessTokens()

        #expect(try await pdf.contents() == FakeGrimmory.pdfBytes(bookID: 9))
        let sent = try #require(server.requests.last)
        #expect(sent.path == "/api/v1/books/9/content")
        // A Book can hold an EPUB too; without bookType the Server sends its primary file.
        #expect(sent.query["bookType"] == "PDF")
        // This endpoint refuses `?token=`, so the header it is, refreshed once when expired.
        #expect(sent.headers["Authorization"] == "Bearer access-2")
        #expect(server.requests.filter { $0.path == "/api/v1/auth/refresh" }.count == 1)
    }

    @Test func signedOutReaderCantOpenAPDF() async throws {
        let account = try await signedIn()
        await account.signOut()

        #expect(await ServerPDF(account: account, bookID: 9) == nil)
    }

    @Test func pageReadOfflineBeforeTheWebReadersIsDroppedForIt() async throws {
        let shared = SharedPositions(account: try await signedIn())
        server.holdSharedPosition(bookID: 9, fixture: "derived-app-progress-pdf")
        // Nov 2023: before the web reader's save on 2026-11-19.
        let clock = TestClock(Date(timeIntervalSince1970: 1_700_000_000))
        let storeURL = FileManager.default.temporaryDirectory
            .appending(path: "dogear-pdf-\(UUID().uuidString)").appending(path: "Positions.store")
        let reading = Positions(store: try PositionStore(url: storeURL), clock: clock)
        try await reading.record(.pdf(PDFLocation(page: 40, throughBook: 0.16)), bookFileID: 21, bookID: 9)

        try await reading.flushOutbox(to: shared)

        #expect(!server.requests.contains { $0.method == "PUT" })
        #expect(await reading.latest(bookFileID: 21)?.location == .pdf(PDFLocation(page: 12, throughBook: 0.048)))
    }
}
