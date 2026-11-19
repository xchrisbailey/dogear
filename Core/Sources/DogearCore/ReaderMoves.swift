/// Tells the reader's own moves through a Book file from relocations. A reader reports a new
/// location whenever it lays the page out again (controls shown or hidden, rotation, reading
/// settings, returning to the app), often a little off where the reader was. Recording one would
/// share a spot the reader never chose, newer than and so winning over reading done elsewhere
/// (ADR 0002).
public struct ReaderMoves: Sendable {
    /// Until the reader moves, wherever the opened page settles is where they already were.
    private var hasMoved = false

    public init() {}

    /// The reader touched the page, pressed a key or chose where to go.
    public mutating func readerMoved() {
        hasMoved = true
    }

    /// The page is being laid out again, or moved to reading done elsewhere.
    public mutating func relocated() {
        hasMoved = false
    }

    /// Whether a location reported now is the reader's reading, to record and share.
    public var isReading: Bool { hasMoved }
}
