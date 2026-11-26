import DogearCore
import Testing

/// The Pocket Player on iPhone Duo's two screens: folded it's a tall phone, open it's a short,
/// wide screen with a crease down the middle, and turned to portrait or stood partly open the
/// crease runs across.
struct FoldTests {
    /// The inner screen open like a book, 951 by 669 points, with a 40-point band down the middle.
    let bookFold = Fold(x: 455.5, y: 0, width: 40, height: 669, viewWidth: 951, viewHeight: 669, isBent: true)

    @Test func aRegionTallerThanWideRunsUpAndDown() throws {
        let fold = try #require(bookFold)

        #expect(fold.direction == .upAndDown)
        #expect(fold.start == 455.5)
        #expect(fold.end == 495.5)
    }

    @Test func aRegionWiderThanTallRunsAcross() throws {
        let fold = try #require(Fold(x: 0, y: 455.5, width: 669, height: 40, viewWidth: 669, viewHeight: 951, isBent: true))

        #expect(fold.direction == .across)
        #expect(fold.start == 455.5)
    }

    /// In a split view the app can sit wholly on one side of the crease.
    @Test func aRegionOutsideTheViewIsNoFold() {
        #expect(Fold(x: 480, y: 0, width: 40, height: 669, viewWidth: 470, viewHeight: 669, isBent: true) == nil)
        #expect(Fold(x: -40, y: 0, width: 40, height: 669, viewWidth: 470, viewHeight: 669, isBent: true) == nil)
        #expect(Fold(x: 0, y: 0, width: 0, height: 0, viewWidth: 470, viewHeight: 669, isBent: false) == nil)
    }

    @Test func aFoldedPhoneIsOneColumn() {
        #expect(PlayerArrangement(width: 466, height: 678, fold: nil) == .column)
    }

    @Test func aWideScreenWithoutAFoldSharesItsWidthEvenly() {
        #expect(PlayerArrangement(width: 678, height: 466, fold: nil) == .sideBySide(nil))
        #expect(PlayerArrangement(width: 1180, height: 820, fold: nil) == .sideBySide(nil))
    }

    @Test func openLikeABookTheColumnsMeetEitherSideOfTheCrease() {
        #expect(PlayerArrangement(width: 951, height: 669, fold: bookFold) == .sideBySide(.init(before: 455.5, gap: 40)))
    }

    /// Lying flat the crease is still there, so the columns still part at it.
    @Test func openFlatTheColumnsStillMeetAtTheCrease() {
        let flat = Fold(x: 455.5, y: 0, width: 40, height: 669, viewWidth: 951, viewHeight: 669, isBent: false)

        #expect(PlayerArrangement(width: 951, height: 669, fold: flat) == .sideBySide(.init(before: 455.5, gap: 40)))
    }

    @Test func aNarrowCreaseStillLeavesTheUsualGap() {
        let hairline = Fold(x: 470, y: 0, width: 10, height: 669, viewWidth: 951, viewHeight: 669, isBent: false)

        #expect(PlayerArrangement(width: 951, height: 669, fold: hairline) == .sideBySide(.init(before: 459, gap: 32)))
    }

    /// Too near an edge, as in a split view, one column would be cramped.
    @Test func aCreaseNearTheEdgeIsIgnored() {
        let offCentre = Fold(x: 120, y: 0, width: 40, height: 669, viewWidth: 760, viewHeight: 669, isBent: true)

        #expect(PlayerArrangement(width: 760, height: 669, fold: offCentre) == .sideBySide(nil))
    }

    @Test func standingLikeALaptopTheControlsGoBelowTheFold() {
        let laptop = Fold(x: 0, y: 455.5, width: 669, height: 40, viewWidth: 669, viewHeight: 951, isBent: true)

        #expect(PlayerArrangement(width: 669, height: 951, fold: laptop) == .aboveAndBelow(.init(before: 455.5, gap: 40)))
    }

    /// Open flat in portrait it's just a tall screen.
    @Test func openFlatInPortraitItIsOneColumn() {
        let flat = Fold(x: 0, y: 455.5, width: 669, height: 40, viewWidth: 669, viewHeight: 951, isBent: false)

        #expect(PlayerArrangement(width: 669, height: 951, fold: flat) == .column)
    }

    @Test func aHalfTooShortForTheControlsIsOneColumn() {
        let low = Fold(x: 0, y: 700, width: 669, height: 40, viewWidth: 669, viewHeight: 951, isBent: true)

        #expect(PlayerArrangement(width: 669, height: 951, fold: low) == .column)
    }
}
