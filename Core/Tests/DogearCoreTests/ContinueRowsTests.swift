import DogearCore
import Foundation
import Testing

/// Continue Reading and Continue Listening: Books with a Shared position, most recent first,
/// including Positions recorded on this device that the Server hasn't seen yet.
struct ContinueRowsTests {
    let server = FakeGrimmory()
    let tokenStore = InMemoryTokenStore()
    /// 2027: after every Shared position the fake Server holds.
    let clock = TestClock(Date(timeIntervalSince1970: 1_800_000_000))
    let directory = FileManager.default.temporaryDirectory.appending(path: "dogear-continue-\(UUID().uuidString)")

    init() {
        server.shelve([
            FakeGrimmory.atomicHabits, FakeGrimmory.flatland, FakeGrimmory.projectHailMary,
            FakeGrimmory.mobyDick, FakeGrimmory.allSystemsRed,
        ])
    }

    func signedInLibrary() async throws -> Library {
        let account = Account(urlSession: server.session, tokenStore: tokenStore, clock: clock)
        _ = try await account.signIn(address: FakeGrimmory.address, username: "reader", password: "correct horse")
        return try library(on: server)
    }

    /// The Library over the store on disk; with an unreachable Server, a relaunch offline.
    func library(on server: FakeGrimmory) throws -> Library {
        Library(
            account: Account(urlSession: server.session, tokenStore: tokenStore, clock: clock),
            store: try LibraryStore(url: directory.appending(path: "Library.store"))
        )
    }

    func positions() throws -> Positions {
        Positions(store: try PositionStore(url: directory.appending(path: "Positions.store")), clock: clock)
    }

    func titles(_ entries: [ContinueEntry]) -> [String] {
        entries.map { "\($0.book.id)/\($0.file.id)" }
    }

    @Test func rowsListBooksWithASharedPositionMostRecentFirst() async throws {
        server.holdContinue(.reading, [
            (9, "2026-11-19T15:41:00Z"), (21, "2026-11-19T15:40:00Z"), (4, "2026-11-19T15:34:09Z"),
        ])
        server.holdContinue(.listening, [(21, "2026-11-19T15:40:00Z"), (5, "2026-11-18T08:00:00Z")])
        let library = try await signedInLibrary()
        _ = try await library.refresh()

        let rows = await library.continueRows(including: [])

        // Moby-Dick has an EPUB and an audiobook: reading opens the EPUB, listening the audiobook.
        #expect(titles(rows.reading) == ["9/21", "21/31", "4/4"])
        #expect(titles(rows.listening) == ["21/32", "5/5"])
        #expect(rows.reading.first?.lastRead == ISO8601DateFormatter().date(from: "2026-11-19T15:41:00Z"))
    }

    @Test func positionsRecordedOfflineMoveRowsBeforeTheServerSeesThem() async throws {
        // The real Server's answers: Atomic Habits in progress, nothing being listened to.
        server.answer("GET", "/api/v1/app/books/continue-reading", with: FakeGrimmory.fixture("continue-reading"))
        server.answer("GET", "/api/v1/app/books/continue-listening", with: FakeGrimmory.fixture("continue-listening-empty"))
        _ = try await signedInLibrary().refresh()
        let offline = try library(on: FakeGrimmory(kind: .unreachable))
        let reading = try positions()

        let pdf = Position.Location.pdf(PDFLocation(page: 12, throughBook: 0.12))
        try await reading.record(pdf, bookFileID: 21, bookID: 9)
        clock.advance(by: 60)
        let audiobook = Position.Location.audiobook(AudiobookLocation(trackIndex: 0, milliseconds: 90_000, throughBook: 0.02))
        try await reading.record(audiobook, bookFileID: 32, bookID: 21)
        // Opened but never read: Grimmory wouldn't list it either.
        try await reading.recordLanding(.audiobook(AudiobookLocation(trackIndex: 0, milliseconds: 0, throughBook: 0)), bookFileID: 5)

        let rows = await offline.continueRows(including: await reading.all())

        #expect(titles(rows.reading) == ["9/21", "4/4"])
        #expect(titles(rows.listening) == ["21/32"])
        #expect(rows.listening.first?.position?.location == audiobook)
    }

    @Test func convertedBooksContinueLikeEPUBs() async throws {
        server.holdContinue(.reading, [(14, "2026-11-19T15:34:09Z")])
        let library = try await signedInLibrary()
        _ = try await library.refresh()
        let reading = try positions()

        #expect(titles(await library.continueRows(including: []).reading) == ["14/14"])

        // Read on this device, an AZW3's Position is an EPUB one.
        let spot = Position.Location.epub(EPUBLocation(href: "section-3.xhtml", throughChapter: 0.5, throughBook: 0.4, cfi: "epubcfi(/6/8!/4/2/1:0)"))
        try await reading.record(spot, bookFileID: 14, bookID: 14)

        let rows = await library.continueRows(including: await reading.all())
        #expect(titles(rows.reading) == ["14/14"])
        #expect(rows.reading.first?.position?.location == spot)
    }

    @Test func bookFinishedOnThisDeviceLeavesContinueReading() async throws {
        server.holdContinue(.reading, [(4, "2026-11-19T15:34:09Z")])
        let library = try await signedInLibrary()
        _ = try await library.refresh()
        let reading = try positions()

        let end = Position.Location.epub(EPUBLocation(href: "OEBPS/end.xhtml", throughChapter: 1, throughBook: 0.998))
        try await reading.record(end, bookFileID: 4, bookID: 4)

        #expect(await library.continueRows(including: await reading.all()).reading.isEmpty)
    }

    @Test func signingOutForgetsTheRows() async throws {
        server.holdContinue(.reading, [(4, "2026-11-19T15:34:09Z")])
        let library = try await signedInLibrary()
        _ = try await library.refresh()

        await library.forget()

        #expect(await library.continueRows(including: []) == ContinueRows())
    }

    @Test func allMergesReadingAndListeningByMostRecentEachFileOnce() async throws {
        server.holdContinue(.reading, [(9, "2026-11-19T15:41:00Z"), (4, "2026-11-19T15:34:09Z")])
        server.holdContinue(.listening, [(21, "2026-11-19T15:40:00Z"), (5, "2026-11-18T08:00:00Z")])
        let library = try await signedInLibrary()
        _ = try await library.refresh()

        let rows = await library.continueRows(including: [])

        #expect(titles(rows.entries(showing: .all)) == ["9/21", "21/32", "4/4", "5/5"])
        #expect(rows.entries(showing: .ebooks) == rows.reading)
        #expect(rows.entries(showing: .audiobooks) == rows.listening)
        #expect(ContinueRows.heading(showing: .all) == "Continue")
        #expect(ContinueRows.heading(showing: .ebooks) == "Continue Reading")
        #expect(ContinueRows.heading(showing: .audiobooks) == "Continue Listening")
    }

    @Test func aBookFileInBothRowsShowsOnceInAll() {
        let book = Book(id: 1, title: "Book", authors: [], files: [BookFile(id: 7, format: .epub, isSupported: true)], primaryFileID: nil, ebookCover: nil, audiobookCover: nil)
        let entry = ContinueEntry(book: book, file: book.files[0], lastRead: Date(timeIntervalSince1970: 10), position: nil)
        let rows = ContinueRows(reading: [entry], listening: [entry])

        #expect(rows.entries(showing: .all).count == 1)
    }
}
