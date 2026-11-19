import Foundation

/// The fake Server's app progress endpoint: one Shared position per Book.
extension FakeGrimmory {
    /// The Shared position the Server reports for `bookID`, from an `app-progress-*` fixture.
    func holdSharedPosition(bookID: Int, fixture: String) {
        state.withLock { $0.sharedPositions[bookID] = fixture }
    }

    static func progress(_ request: Request, state: State) -> FakeServer.Reply? {
        let parts = request.path.split(separator: "/").map(String.init)
        guard parts.count == 6, parts.starts(with: ["api", "v1", "app", "books"]), parts[5] == "progress",
              let bookID = Int(parts[4])
        else { return nil }
        guard isAuthorized(request, state: state) else {
            return fixture("error-401-unauthenticated", status: 401)
        }
        switch request.method {
        case "GET": return fixture(state.sharedPositions[bookID] ?? "app-progress-empty")
        case "PUT": return .response(status: 200, body: Data())
        default: return nil
        }
    }
}
