import DogearCore
import Foundation
import Synchronization

final class TestClock: WallClock {
    private let current: Mutex<Date>

    init(_ start: Date = Date(timeIntervalSince1970: 1_800_000_000)) {
        current = Mutex(start)
    }

    func now() -> Date { current.withLock { $0 } }
    func advance(by seconds: TimeInterval) { current.withLock { $0 += seconds } }
}

/// Stands in for the Keychain, which needs entitlements `swift test` doesn't have.
/// Share one instance between two `Account`s to simulate a relaunch.
final class InMemoryTokenStore: TokenStore {
    private let stored = Mutex<Session?>(nil)

    var session: Session? { stored.withLock { $0 } }

    func load() -> Session? { session }
    func save(_ session: Session) throws { stored.withLock { $0 = session } }
    func clear() { stored.withLock { $0 = nil } }
}
