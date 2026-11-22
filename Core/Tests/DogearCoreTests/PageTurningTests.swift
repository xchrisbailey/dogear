import DogearCore
import Testing

/// Turning the pages of an open Book by tap and by drag.
struct PageTurningTests {
    @Test(arguments: [
        (10.0, PageTap.turn(.backward)),
        (100.0, .turn(.backward)),
        (120.0, .controls),
        (200.0, .controls),
        (260.0, .controls),
        (280.0, .turn(.forward)),
        (389.0, .turn(.forward)),
    ])
    func aTapTurnsAtTheEdgesAndShowsControlsInTheMiddle(x: Double, does: PageTap) {
        #expect(PageTap(x: x, width: 390, rightToLeft: false) == does)
    }

    @Test func aRightToLeftBookMirrorsTheTapZones() {
        #expect(PageTap(x: 10, width: 390, rightToLeft: true) == .turn(.forward))
        #expect(PageTap(x: 380, width: 390, rightToLeft: true) == .turn(.backward))
        #expect(PageTap(x: 195, width: 390, rightToLeft: true) == .controls)
    }

    @Test func aTapReportedAPageOutCountsWhereItFellOnThePage() {
        #expect(PageTap(x: 330 - 390, width: 390, rightToLeft: false) == .turn(.forward))
        #expect(PageTap(x: 40 + 390, width: 390, rightToLeft: false) == .turn(.backward))
        #expect(PageTap(x: 195 - 780, width: 390, rightToLeft: false) == .controls)
    }

    @Test func aTapBeforeThePageHasASizeTurnsNothing() {
        #expect(PageTap(x: 0, width: 0, rightToLeft: false) == .controls)
    }

    @Test func draggingTowardTheSpineTurnsForward() {
        #expect(PageDrag(translation: -8, width: 390, rightToLeft: false)?.turn == .forward)
        #expect(PageDrag(translation: 8, width: 390, rightToLeft: false)?.turn == .backward)
        #expect(PageDrag(translation: 8, width: 390, rightToLeft: true)?.turn == .forward)
        #expect(PageDrag(translation: -8, width: 390, rightToLeft: true)?.turn == .backward)
        #expect(PageDrag(translation: 0, width: 390, rightToLeft: false) == nil)
    }

    @Test func thePageFollowsTheFinger() throws {
        let forward = try #require(PageDrag(translation: -8, width: 400, rightToLeft: false))
        #expect(forward.progress(translation: -100) == 0.25)
        #expect(forward.progress(translation: -900) == 1)
        // Dragged back past where it started, the page lies flat; it doesn't turn the other way.
        #expect(forward.progress(translation: 50) == 0)

        let backward = try #require(PageDrag(translation: 8, width: 400, rightToLeft: false))
        #expect(backward.progress(translation: 200) == 0.5)
        #expect(backward.progress(translation: -20) == 0)
    }

    @Test func lettingGoPastHalfwayFinishesTheTurn() throws {
        let drag = try #require(PageDrag(translation: -8, width: 400, rightToLeft: false))
        #expect(drag.completes(translation: -220, velocity: 0))
        #expect(!drag.completes(translation: -150, velocity: 0))
    }

    @Test func aFlickDecidesWhateverThePosition() throws {
        let drag = try #require(PageDrag(translation: -8, width: 400, rightToLeft: false))
        #expect(drag.completes(translation: -40, velocity: -900))
        #expect(!drag.completes(translation: -300, velocity: 900))

        let back = try #require(PageDrag(translation: 8, width: 400, rightToLeft: false))
        #expect(back.completes(translation: 40, velocity: 900))
        #expect(!back.completes(translation: 300, velocity: -900))
    }

    @Test func quickTapsQueueOneExtraTurnAndNeverDropAPage() {
        var queue = PageTurnQueue()
        #expect(queue.request(.forward) == .forward)
        #expect(queue.request(.forward) == nil)
        // A third tap replaces the one waiting; it doesn't stack.
        #expect(queue.request(.backward) == nil)
        #expect(queue.finished() == .backward)
        #expect(queue.finished() == nil)
        #expect(queue.request(.forward) == .forward)
    }

    @Test func aTurnStartsAtOnceWhenNothingIsTurning() {
        var queue = PageTurnQueue()
        #expect(queue.isIdle)
        #expect(queue.request(.forward) == .forward)
        #expect(!queue.isIdle)
        #expect(queue.finished() == nil)
        #expect(queue.isIdle)
        #expect(queue.request(.backward) == .backward)
    }

    @Test func aPageFlipsOnlyWhenOneWholePageCanSwing() {
        #expect(PageTurnStyle(scrolls: false, pagesSideBySide: false, fixedLayout: false, reduceMotion: false) == .flip)
        #expect(PageTurnStyle(scrolls: false, pagesSideBySide: true, fixedLayout: false, reduceMotion: false) == .fade)
        #expect(PageTurnStyle(scrolls: false, pagesSideBySide: false, fixedLayout: true, reduceMotion: false) == .fade)
        #expect(PageTurnStyle(scrolls: false, pagesSideBySide: false, fixedLayout: false, reduceMotion: true) == .fade)
        #expect(PageTurnStyle(scrolls: true, pagesSideBySide: false, fixedLayout: false, reduceMotion: true) == .none)
    }
}
