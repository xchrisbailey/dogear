/// The fold down the middle of a foldable iPhone's inner screen (iPhone Duo), where the system
/// asks content to divide into two regions.
///
/// Measured in the coordinates of the view laying out, so a region the system reports in points
/// becomes a band across that view: up and down it when the phone opens like a book, across it
/// when the open phone is turned to portrait.
public struct Fold: Equatable, Sendable {
    public enum Direction: Equatable, Sendable {
        /// The fold runs top to bottom, splitting the view into leading and trailing halves.
        case upAndDown
        /// The fold runs side to side, splitting the view into top and bottom halves.
        case across
    }

    public let direction: Direction
    /// Where the band starts, from the view's leading edge for a fold up and down, or its top
    /// for one across.
    public let start: Double
    /// How wide the band is, including the margin the system keeps clear of controls.
    public let length: Double
    /// The phone is partly open, so the two halves face different ways. A flat open phone still
    /// has its crease, but content may run over it.
    public let isBent: Bool

    public var end: Double { start + length }

    /// A fold from the system's division region, at `x`, `y`, `width` and `height` in a view
    /// `viewWidth` by `viewHeight`. nil when the region doesn't cross the view, as when the view
    /// is beside the fold in a split view.
    public init?(x: Double, y: Double, width: Double, height: Double, viewWidth: Double, viewHeight: Double, isBent: Bool) {
        guard width > 0, height > 0, viewWidth > 0, viewHeight > 0 else { return nil }
        if height >= width {
            guard x > 0, x + width < viewWidth else { return nil }
            direction = .upAndDown
            start = x
            length = width
        } else {
            guard y > 0, y + height < viewHeight else { return nil }
            direction = .across
            start = y
            length = height
        }
        self.isBent = isBent
    }
}

/// How the Pocket Player shares out its screen: the title and the player illustration, and the
/// working controls.
public enum PlayerArrangement: Equatable, Sendable {
    /// One column down a tall screen.
    case column
    /// The title and player beside the controls, in a short, wide screen. With a `Split`, the
    /// columns end either side of a fold; without one they share the width evenly.
    case sideBySide(Split?)
    /// The title and player above a fold, the controls below it, as when a partly open phone
    /// stands like a laptop with its lower half lying flat.
    case aboveAndBelow(Split)

    /// Where two regions meet: the first runs from the view's edge to `before`, then `gap` is
    /// left clear for the fold.
    public struct Split: Equatable, Sendable {
        public let before: Double
        public let gap: Double

        public init(before: Double, gap: Double) {
            self.before = before
            self.gap = gap
        }
    }

    /// Narrower than this, the two columns don't fit beside each other.
    public static let sideBySideMinWidth = 560.0
    /// The least a column beside a fold needs for the player or the controls.
    static let minColumn = 240.0
    /// The least each half needs above and below a fold: the controls are about 270 tall.
    static let minHalf = 280.0
    /// The least clear space kept between the columns, fold or not.
    static let minGap = 32.0

    public init(width: Double, height: Double, fold: Fold?) {
        // Standing partly open like a laptop: the controls go on the half lying flat.
        if let fold, fold.direction == .across, fold.isBent,
           fold.start >= Self.minHalf, height - fold.end >= Self.minHalf {
            self = .aboveAndBelow(Split(before: fold.start, gap: fold.length))
            return
        }
        guard width >= Self.sideBySideMinWidth, height < width else {
            self = .column
            return
        }
        // Open like a book, bent or flat: the columns meet at the crease rather than across it.
        if let fold, fold.direction == .upAndDown {
            let gap = max(fold.length, Self.minGap)
            let before = fold.start + fold.length / 2 - gap / 2
            if before >= Self.minColumn, width - before - gap >= Self.minColumn {
                self = .sideBySide(Split(before: before, gap: gap))
                return
            }
        }
        self = .sideBySide(nil)
    }
}
