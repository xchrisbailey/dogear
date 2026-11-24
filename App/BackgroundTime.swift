import UIKit

/// Asks iOS for a little more time when the app leaves the screen, so the last Position read
/// reaches the Server before the app is suspended. Without it, a phone locked straight after
/// reading keeps that Position in the Outbox until the app is opened there again, and another
/// device opens the Book at an older place.
@MainActor
final class BackgroundTime {
    private var task = UIBackgroundTaskIdentifier.invalid

    static func finish(_ name: String, _ work: @escaping @MainActor () async -> Void) {
        let time = BackgroundTime()
        time.task = UIApplication.shared.beginBackgroundTask(withName: name) {
            // Out of time: whatever is left stays in the Outbox for the next flush.
            MainActor.assumeIsolated { time.end() }
        }
        Task { @MainActor in
            await work()
            time.end()
        }
    }

    private func end() {
        guard task != .invalid else { return }
        UIApplication.shared.endBackgroundTask(task)
        task = .invalid
    }
}
