import Foundation

/// The fake Server's Continue Reading and Continue Listening lists.
extension FakeGrimmory {
    enum ContinueList: String, Sendable {
        case reading = "continue-reading"
        case listening = "continue-listening"
    }

    /// The Books the Server lists, in the order given (most recent first, as Grimmory sorts),
    /// each with its per-Book `lastReadTime`.
    func holdContinue(_ list: ContinueList, _ rows: [(bookID: Int, lastReadTime: String)]) {
        state.withLock { $0.continueRows[list.rawValue] = rows }
    }

    static func continueList(_ request: Request, state: State) -> FakeServer.Reply? {
        let parts = request.path.split(separator: "/").map(String.init)
        guard request.method == "GET", parts.count == 5, parts.starts(with: ["api", "v1", "app", "books"]),
              let list = ContinueList(rawValue: parts[4])
        else { return nil }
        guard isAuthorized(request, state: state) else {
            return fixture("error-401-unauthenticated", status: 401)
        }
        let summaries = (state.continueRows[list.rawValue] ?? []).compactMap { row -> [String: Any]? in
            guard var summary = state.library.first(where: { $0.id == row.bookID })?.detailJSON else { return nil }
            summary["lastReadTime"] = row.lastReadTime
            summary["readStatus"] = "READING"
            return summary
        }
        return .response(status: 200, body: try! JSONSerialization.data(withJSONObject: summaries))
    }
}
