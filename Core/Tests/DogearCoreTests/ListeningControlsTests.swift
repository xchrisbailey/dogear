import DogearCore
import Foundation
import Testing

/// The listener's controls, in whole-book time so they behave the same whichever Track is playing.
struct ListeningControlsTests {
    let server = FakeGrimmory()

    /// Project Hail Mary (single file, Chapters at 0, 2 224 936, 3 946 417 and 57 371 538 ms) or
    /// Slaughterhouse-Five (folder, no Chapters, Tracks of 320 365, 420 362 and 199 601 ms first).
    func info(_ book: FakeGrimmory.ShelvedBook, id: Int) async throws -> AudiobookInfo {
        server.shelve([book])
        let account = Account(urlSession: server.session, tokenStore: InMemoryTokenStore())
        _ = try await account.signIn(address: FakeGrimmory.address, username: "reader", password: "correct horse")
        return try await #require(await ServerAudiobook(account: account, bookID: id)).info()
    }

    @Test func endOfChapterStopsWhenThePlayingChapterEnds() async throws {
        let info = try await info(FakeGrimmory.projectHailMary, id: 5)
        var timer = SleepTimer(.endOfChapter, at: .milliseconds(3_000_000), in: info)

        let beforeTheEnd = timer.played(.seconds(0.5), to: .milliseconds(3_946_000))
        let atTheEnd = timer.played(.seconds(0.5), to: .milliseconds(3_946_417))

        #expect(!beforeTheEnd)
        #expect(atTheEnd)
    }

    @Test func skippingBackIntoTheChapterBeforeStopsAtTheEndOfThatChapter() async throws {
        let info = try await info(FakeGrimmory.projectHailMary, id: 5)
        var timer = SleepTimer(.endOfChapter, at: .milliseconds(2_230_000), in: info)

        let landed = info.skip(from: .milliseconds(2_230_000), by: .seconds(-15))
        timer.moved(to: landed, in: info)
        let atTheEndOfTheEarlierChapter = timer.played(.seconds(0.5), to: .milliseconds(2_224_936))

        #expect(landed == .milliseconds(2_215_000))
        #expect(info.chapter(at: landed)?.index == 0)
        #expect(atTheEndOfTheEarlierChapter)
    }

    /// The Server reads no Chapters from folder audiobooks; their Tracks are the natural breaks.
    @Test func endOfChapterInAFolderAudiobookStopsWhenTheTrackEnds() async throws {
        let info = try await info(FakeGrimmory.slaughterhouseFive, id: 6)
        // 100 s into Track 1, which ends 740 727 ms into the book.
        var timer = SleepTimer(.endOfChapter, at: .milliseconds(420_365), in: info)

        let beforeTheEnd = timer.played(.seconds(0.5), to: .milliseconds(740_000))
        let intoTheNextTrack = timer.played(.seconds(0.5), to: .milliseconds(740_900))

        #expect(!beforeTheEnd)
        #expect(intoTheNextTrack)
    }

    /// Only time spent playing counts, so a pause doesn't eat into the timer.
    @Test func timedSleepStopsAfterThatMuchListening() async throws {
        let info = try await info(FakeGrimmory.projectHailMary, id: 5)
        var timer = SleepTimer(.after(.seconds(15 * 60)), at: .zero, in: info)

        let afterTenMinutes = timer.played(.seconds(10 * 60), to: .seconds(10 * 60))
        let leftAfterTen = timer.remaining
        let afterFifteenMinutes = timer.played(.seconds(5 * 60), to: .seconds(15 * 60))

        #expect(!afterTenMinutes)
        #expect(leftAfterTen == .seconds(5 * 60))
        #expect(afterFifteenMinutes)
        #expect(timer.remaining == .zero)
    }

    @Test func savedListeningSettingsComeBack() {
        let settings = ListeningSettings(storedSkipBack: 10, storedSkipForward: 60, storedSpeed: 1.5)

        #expect(settings == ListeningSettings(skipBack: .seconds(10), skipForward: .seconds(60), speed: 1.5))
    }

    /// Nothing saved yet reads as zeros from UserDefaults; a value an older Dogear offered may be gone.
    @Test(arguments: [(nil, nil, nil), (0, 0, 0), (17, 300, 0.6)] as [(Int?, Int?, Float?)])
    func unknownListeningSettingsFallBackToTheStandardOnes(back: Int?, forward: Int?, speed: Float?) {
        let settings = ListeningSettings(storedSkipBack: back, storedSkipForward: forward, storedSpeed: speed)

        #expect(settings == .standard)
        #expect(settings.skipBack == .seconds(15))
        #expect(settings.skipForward == .seconds(30))
        #expect(settings.speed == 1)
    }
}
