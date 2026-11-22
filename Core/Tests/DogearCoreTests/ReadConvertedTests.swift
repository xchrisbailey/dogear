import DogearCore
import Foundation
import Testing

/// MOBI, AZW3 and FB2 Book files: fetched whole, as the web reader loads them, and read as EPUBs,
/// with Positions Grimmory stores as EPUB ones (ADR 0005).
struct ReadConvertedTests {
    let server = FakeGrimmory()

    func signedIn() async throws -> Account {
        server.shelve([FakeGrimmory.allSystemsRed, FakeGrimmory.mobyDick])
        let account = Account(urlSession: server.session, tokenStore: InMemoryTokenStore())
        _ = try await account.signIn(address: FakeGrimmory.address, username: "reader", password: "correct horse")
        return account
    }

    @Test func azw3IsFetchedWholeWithTheAccessToken() async throws {
        let account = try await signedIn()
        let azw3 = try #require(await ServerConvertible(account: account, bookID: 14, format: .azw3))
        server.expireAccessTokens()

        #expect(try await azw3.contents() == FakeGrimmory.contentBytes(bookID: 14, bookType: "AZW3"))
        let sent = try #require(server.requests.last)
        #expect(sent.path == "/api/v1/books/14/content")
        #expect(sent.query["bookType"] == "AZW3")
    }

    @Test func aMOBIBesideAnEPUBIsPickedByItsFormat() async throws {
        let account = try await signedIn()
        let mobi = try #require(await ServerConvertible(account: account, bookID: 21, format: .mobi))

        #expect(try await mobi.contents() == FakeGrimmory.contentBytes(bookID: 21, bookType: "MOBI"))
        // Moby-Dick has no FB2.
        let fb2 = try #require(await ServerConvertible(account: account, bookID: 21, format: .fb2))
        await #expect(throws: RequestError.notFound) { try await fb2.contents() }
    }

    @Test func onlyMOBIAZW3AndFB2AreConverted() async throws {
        let account = try await signedIn()

        #expect(await ServerConvertible(account: account, bookID: 21, format: .epub) == nil)
        #expect(await ServerConvertible(account: account, bookID: 21, format: .comic) == nil)
        #expect([BookFile.Format.mobi, .azw3, .fb2].allSatisfy(\.isConvertedToEPUB))
        #expect(BookFile.Format.ebooks == [.epub, .azw3, .mobi, .fb2, .pdf])
    }

    @Test func webReadersAZW3PositionComesBackAsAnEPUBPosition() async throws {
        let shared = SharedPositions(account: try await signedIn())
        // Grimmory saves an AZW3's Position in the same fields as an EPUB's.
        server.holdSharedPosition(bookID: 14, fixture: "app-progress-epub")

        let position = try #require(try await shared.latest(.azw3, bookID: 14, bookFileID: 14))

        guard case let .epub(location) = position.location else {
            Issue.record("not an EPUB location")
            return
        }
        #expect(location.cfi == "epubcfi(/6/30!/4[x9780735211308_EPUB-13],/2/34,/6/10/3:74)")
        #expect(position.bookFileID == 14)
        #expect(try await shared.latest(.epub, bookID: 14, bookFileID: 14) == position)
    }

    @Test func azw3PositionIsPushedAsFileProgressForItsBookFile() async throws {
        let shared = SharedPositions(account: try await signedIn())
        let position = Position(
            bookFileID: 14,
            location: .epub(EPUBLocation(href: "section-3.xhtml", throughChapter: 0.5, throughBook: 0.4, cfi: "epubcfi(/6/8!/4/2/1:0)")),
            recordedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        try await shared.push(position, bookID: 14)

        let fileProgress = try #require(server.requests.last?.json?["fileProgress"] as? [String: any Sendable])
        #expect(fileProgress["bookFileId"] as? Int == 14)
        #expect(fileProgress["positionData"] as? String == "epubcfi(/6/8!/4/2/1:0)")
        #expect(fileProgress["progressPercent"] as? Double == 40)
    }
}
