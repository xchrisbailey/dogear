import DogearCore
import Foundation
import Testing

/// Positions kept on the device, so reopening a Book file resumes where the reader left off.
struct PositionTests {
    let clock = TestClock()
    let storeURL = FileManager.default.temporaryDirectory
        .appending(path: "dogear-positions-\(UUID().uuidString)")
        .appending(path: "Positions.store")

    /// Positions over the store on disk; a second call simulates a relaunch.
    func positions() throws -> Positions {
        Positions(store: try PositionStore(url: storeURL), clock: clock)
    }

    let chapter3 = Position.Location.epub(EPUBLocation(
        href: "OEBPS/ch03.xhtml", chapterProgress: 0.4, bookProgress: 0.21, readerState: #"{"href":"OEBPS/ch03.xhtml"}"#
    ))
    let chapter4 = Position.Location.epub(EPUBLocation(
        href: "OEBPS/ch04.xhtml", chapterProgress: 0.1, bookProgress: 0.27, readerState: #"{"href":"OEBPS/ch04.xhtml"}"#
    ))

    @Test func latestPositionIsThereAfterRelaunch() async throws {
        let reading = try positions()
        try await reading.record(chapter3, bookFileID: 4, bookID: 4)
        clock.advance(by: 90)
        try await reading.record(chapter4, bookFileID: 4, bookID: 4)
        try await reading.record(chapter3, bookFileID: 31, bookID: 7)

        let relaunched = try positions()

        let resumed = try #require(await relaunched.latest(bookFileID: 4))
        #expect(resumed.location == chapter4)
        // Device time, which the conflict rule (ADR 0002) compares with the Server's.
        #expect(resumed.recordedAt == Date(timeIntervalSince1970: 1_800_000_090))
        #expect(await relaunched.latest(bookFileID: 31)?.location == chapter3)
        #expect(await relaunched.latest(bookFileID: 99) == nil)
    }

    @Test func forgettingPositionsLeavesNothingToResume() async throws {
        let reading = try positions()
        try await reading.record(chapter3, bookFileID: 4, bookID: 4)

        await reading.forget()

        let relaunched = try positions()
        #expect(await relaunched.latest(bookFileID: 4) == nil)
        // Signing out discards unsent reading too; the app warns first.
        #expect(await relaunched.outboxCount() == 0)
    }
}
