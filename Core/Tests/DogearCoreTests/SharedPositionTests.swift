import DogearCore
import Foundation
import Testing

/// EPUB Positions shared with Grimmory's web reader through the app progress endpoint.
struct SharedPositionTests {
    let server = FakeGrimmory()

    func signedIn() async throws -> SharedPositions {
        server.shelve([FakeGrimmory.atomicHabits])
        let account = Account(urlSession: server.session, tokenStore: InMemoryTokenStore())
        _ = try await account.signIn(address: FakeGrimmory.address, username: "reader", password: "correct horse")
        return SharedPositions(account: account)
    }

    @Test func pushSendsTheCFIAndItsFallbacksAsFileProgressOnly() async throws {
        let shared = try await signedIn()
        let position = Position(
            bookFileID: 4,
            location: .epub(EPUBLocation(
                href: "OEBPS/xhtml/15_7_The_Secret_to_Self-.xhtml",
                throughChapter: 0.5,
                throughBook: 0.25,
                cfi: "epubcfi(/6/30!/4[x9780735211308_EPUB-13]/2/8/3:190)",
                readerState: #"{"href":"OEBPS/xhtml/15_7_The_Secret_to_Self-.xhtml"}"#
            )),
            recordedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        try await shared.push(position, bookID: 4)

        let sent = try #require(server.requests.last)
        #expect(sent.method == "PUT")
        #expect(sent.path == "/api/v1/app/books/4/progress")
        // Deprecated per-type fields would be saved over the CFI, so only fileProgress goes.
        #expect(sent.json?.keys.sorted() == ["fileProgress"])
        let fileProgress = try #require(sent.json?["fileProgress"] as? [String: any Sendable])
        #expect(fileProgress.keys.sorted() == ["bookFileId", "contentSourceProgressPercent", "positionData", "positionHref", "progressPercent"])
        #expect(fileProgress["bookFileId"] as? Int == 4)
        #expect(fileProgress["positionData"] as? String == "epubcfi(/6/30!/4[x9780735211308_EPUB-13]/2/8/3:190)")
        #expect(fileProgress["positionHref"] as? String == "OEBPS/xhtml/15_7_The_Secret_to_Self-.xhtml")
        #expect(fileProgress["progressPercent"] as? Double == 25)
        #expect(fileProgress["contentSourceProgressPercent"] as? Double == 50)
    }

    @Test func aProgressJSONCannotHoldIsSentAsZeroRatherThanAnEmptyBody() async throws {
        let shared = try await signedIn()
        let position = Position(
            bookFileID: 4,
            location: .epub(EPUBLocation(href: "OEBPS/ch01.xhtml", throughChapter: .nan, throughBook: .infinity, cfi: "epubcfi(/6/8!/4/2/1:0)")),
            recordedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        try await shared.push(position, bookID: 4)

        let fileProgress = try #require(server.requests.last?.json?["fileProgress"] as? [String: any Sendable])
        #expect(fileProgress["progressPercent"] as? Double == 0)
        #expect(fileProgress["contentSourceProgressPercent"] as? Double == 0)
    }

    @Test func webReadersPositionComesBackWithItsCFIAndFallbacks() async throws {
        let shared = try await signedIn()
        server.holdSharedPosition(bookID: 4, fixture: "app-progress-epub")

        let position = try #require(try await shared.latest(.epub, bookID: 4, bookFileID: 4))

        #expect(position.bookFileID == 4)
        #expect(position.recordedAt == ISO8601DateFormatter().date(from: "2026-11-19T15:34:09Z"))
        guard case let .epub(location) = position.location else { Issue.record("not an EPUB Position"); return }
        #expect(location.cfi == "epubcfi(/6/30!/4[x9780735211308_EPUB-13],/2/34,/6/10/3:74)")
        // The web reader's href points at a page-list anchor; the resource is what matters.
        #expect(location.href == "OEBPS/xhtml/15_7_The_Secret_to_Self-.xhtml")
        #expect(location.throughBook == 0.281341)
        #expect(location.throughChapter == 0)
        #expect(location.readerState == nil)
    }

    @Test func bookNeverOpenedElsewhereHasNoSharedPosition() async throws {
        let shared = try await signedIn()
        server.holdSharedPosition(bookID: 4, fixture: "app-progress-empty")

        #expect(try await shared.latest(.epub, bookID: 4, bookFileID: 4) == nil)
    }
}
