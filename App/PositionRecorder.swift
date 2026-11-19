import DogearCore
import Foundation

/// Saves a reader's or player's Positions in one Book, one after another, so a slow save can't
/// land after a newer one and win.
final class PositionRecorder {
    private let bookID: Int
    private let positions: Positions?
    private let sharedPositions: SharedPositions?
    private var recording: Task<Void, Never>?

    init(bookID: Int, positions: Positions?, sharedPositions: SharedPositions?) {
        self.bookID = bookID
        self.positions = positions
        self.sharedPositions = sharedPositions
    }

    /// Saves where the reader is. `share` adds it to the Outbox and then runs `afterSharing`;
    /// otherwise it's where they landed on opening, which they already were.
    func record(
        bookFileID: Int, share: Bool,
        location: @escaping () async -> Position.Location,
        afterSharing: @escaping () async -> Void = {}
    ) {
        recording = Task { [previous = recording, positions, sharedPositions, bookID] in
            let location = await location()
            await previous?.value
            guard let positions else {
                // Without the on-device store there's no Outbox; sharing directly is the best left.
                if share {
                    let position = Position(bookFileID: bookFileID, location: location, recordedAt: Date())
                    try? await sharedPositions?.push(position, bookID: bookID)
                }
                return
            }
            if share {
                _ = try? await positions.record(location, bookFileID: bookFileID, bookID: bookID)
                await afterSharing()
            } else {
                _ = try? await positions.recordLanding(location, bookFileID: bookFileID)
            }
        }
    }

    /// Waits for every Position recorded so far to be saved.
    func finished() async {
        await recording?.value
    }
}
