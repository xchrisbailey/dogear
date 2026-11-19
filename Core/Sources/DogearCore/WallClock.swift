import Foundation

/// Injectable source of the current time. Named to avoid clashing with Swift's `Clock`.
public protocol WallClock: Sendable {
    func now() -> Date
}

public struct SystemClock: WallClock {
    public init() {}
    public func now() -> Date { Date() }
}
