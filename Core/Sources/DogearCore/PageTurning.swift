/// Which way a page turns through a Book file.
public enum PageTurn: Sendable, Equatable {
    case forward
    case backward
}

/// How the reader shows a move from one page to the next.
public enum PageTurnStyle: Sendable, Equatable {
    /// The page lifts from its outer edge and swings about the spine.
    case flip
    /// One page fades into the next.
    case fade
    /// The reader moves by scrolling, so there is no page to turn.
    case none

    /// A flip needs one whole page to swing. Two pages side by side and fixed-layout Books fade
    /// for now, and Reduce Motion always does.
    public init(scrolls: Bool, pagesSideBySide: Bool, fixedLayout: Bool, reduceMotion: Bool) {
        self = if scrolls { .none }
        else if pagesSideBySide || fixedLayout || reduceMotion { .fade }
        else { .flip }
    }
}

/// What a tap on the page does, by where it lands across the page.
public enum PageTap: Sendable, Equatable {
    case turn(PageTurn)
    /// Shows or hides the reader's controls.
    case controls

    /// The outer third of the page turns forward and the third by the spine turns back, as a
    /// thumb on a paper page would. The outer third is a little wider, since forward is what a
    /// reader does most.
    ///
    /// The reader places a tap by how far its page has scrolled, so one that lands while a turn
    /// is moving the page can be reported whole pages to either side. It counts where it fell on
    /// the page.
    public init(x: Double, width: Double, rightToLeft: Bool) {
        guard width > 0 else {
            self = .controls
            return
        }
        let across = (x.truncatingRemainder(dividingBy: width) + width).truncatingRemainder(dividingBy: width)
        // Distance from the spine, as a share of the page.
        let fromSpine = rightToLeft ? 1 - across / width : across / width
        self = if fromSpine < 0.28 { .turn(.backward) }
        else if fromSpine > 0.68 { .turn(.forward) }
        else { .controls }
    }
}

/// A finger dragging a page over.
public struct PageDrag: Sendable, Equatable {
    public let turn: PageTurn
    private let width: Double
    private let rightToLeft: Bool

    /// A flick this fast, in points a second, carries the page over or back whatever its position.
    static let flick = 400.0

    /// Starts from the first movement: toward the spine turns forward, away from it turns back.
    /// nil when the finger hasn't moved sideways.
    public init?(translation: Double, width: Double, rightToLeft: Bool) {
        guard translation != 0, width > 0 else { return nil }
        self.width = width
        self.rightToLeft = rightToLeft
        let towardSpine = rightToLeft ? translation > 0 : translation < 0
        turn = towardSpine ? .forward : .backward
    }

    /// Movement in the direction this drag turns the page.
    private func along(_ sideways: Double) -> Double {
        let towardSpine = rightToLeft ? sideways : -sideways
        return turn == .forward ? towardSpine : -towardSpine
    }

    /// How far over the page is, 0 where it lay to 1 fully turned, for the finger `translation`
    /// points from where it started. A page's width of travel turns it all the way.
    public func progress(translation: Double) -> Double {
        min(max(along(translation) / width, 0), 1)
    }

    /// Whether letting go here finishes the turn: past halfway, or flicked onward. A flick the
    /// other way always puts the page back.
    public func completes(translation: Double, velocity: Double) -> Bool {
        let speed = along(velocity)
        if speed > Self.flick { return true }
        if speed < -Self.flick { return false }
        return progress(translation: translation) >= 0.5
    }
}

/// Page turns asked for faster than they can be shown. One more than the turn in the air is
/// remembered, so quick taps never drop a page and never run away either.
public struct PageTurnQueue: Sendable {
    private var isTurning = false
    private var waiting: PageTurn?

    public init() {}

    /// Nothing is in the air or waiting.
    public var isIdle: Bool { !isTurning }

    /// Asks for a turn. Returns it when it should start now; otherwise it waits for `finished`.
    public mutating func request(_ turn: PageTurn) -> PageTurn? {
        guard isTurning else {
            isTurning = true
            return turn
        }
        waiting = turn
        return nil
    }

    /// The turn in the air has landed. Returns the one to start next, if any.
    public mutating func finished() -> PageTurn? {
        let next = waiting
        waiting = nil
        isTurning = next != nil
        return next
    }
}
