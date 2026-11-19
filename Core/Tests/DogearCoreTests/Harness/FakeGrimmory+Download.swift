import DogearCore
import Foundation
import Synchronization

/// The fake Server's download endpoints and the reader's permissions.
extension FakeGrimmory {
    func setPermissions(canDownload: Bool, isAdmin: Bool = false) {
        state.withLock {
            $0.canDownload = canDownload
            $0.isAdmin = isAdmin
        }
    }

    static func download(_ request: Request, state: State) -> FakeServer.Reply? {
        let parts = request.path.split(separator: "/").map(String.init)
        guard request.method == "GET", parts.starts(with: ["api", "v1"]) else { return nil }
        let route = Array(parts.dropFirst(2))
        let isDownloadRoute = route == ["app", "users", "me"]
            || (route.count == 3 && route[0] == "books" && route[2] == "download")
            || (route.count == 5 && route[0] == "books" && route[2] == "files" && route[4] == "download")
        guard isDownloadRoute else { return nil }
        guard isAuthorized(request, state: state) else {
            return fixture("error-401-unauthenticated", status: 401)
        }
        if route == ["app", "users", "me"] {
            return fixture("app-users-me", replacing: [
                "\"canDownload\": true": "\"canDownload\": \(state.canDownload)",
                "\"admin\": false": "\"admin\": \(state.isAdmin)",
            ])
        }
        guard let book = state.library.first(where: { String($0.id) == route[1] }) else {
            return fixture("error-404-book", status: 404)
        }
        let files = book.detailJSON["files"] as? [[String: Any]] ?? []
        let primary = files.first { $0["primary"] as? Bool == true }
        if route.count == 3 {
            // Only the primary file, and only with the permission.
            guard state.canDownload || state.isAdmin else { return fixture("error-403", status: 403) }
            return .response(status: 200, body: fileBytes(bookID: book.id, fileID: primary?["id"] as? Int ?? 0), contentType: "application/octet-stream")
        }
        // Grimmory doesn't check the permission here, so Dogear has to.
        guard let fileID = Int(route[3]), files.contains(where: { $0["id"] as? Int == fileID }) else {
            return fixture("error-404-book", status: 404)
        }
        guard primary?["id"] as? Int != fileID else { return .response(status: 400, body: Data()) }
        return .response(status: 200, body: fileBytes(bookID: book.id, fileID: fileID), contentType: "application/octet-stream")
    }

    /// Stand-in Book file bytes, distinct per Book file.
    static func fileBytes(bookID: Int, fileID: Int) -> Data {
        Data("file-\(bookID)-\(fileID)".utf8)
    }
}

/// Stands in for the background URLSession, which ignores the fake Server: fetches each transfer
/// through the fake Server and reports back as the session's delegate would.
final class FakeTransport: DownloadTransport {
    private let session: URLSession
    private let state = Mutex<(downloads: Downloads?, holding: Bool, held: [DownloadTransfer], started: [DownloadTransfer])>((nil, false, [], []))

    init(server: FakeGrimmory) {
        session = server.session
    }

    func attach(_ downloads: Downloads) {
        state.withLock { $0.downloads = downloads }
    }

    /// Transfers start but don't finish until `release()`, as a big download in progress.
    func hold() {
        state.withLock { $0.holding = true }
    }

    func release() async {
        let held = state.withLock { state in
            state.holding = false
            defer { state.held = [] }
            return state.held
        }
        for transfer in held { await finish(transfer) }
    }

    var started: [DownloadTransfer] { state.withLock { $0.started } }

    func start(_ transfer: DownloadTransfer) async {
        let holding = state.withLock { state in
            state.started.append(transfer)
            if state.holding { state.held.append(transfer) }
            return state.holding
        }
        if !holding { await finish(transfer) }
    }

    func cancel(_ transferIDs: [String]) async {
        state.withLock { state in state.held.removeAll { transferIDs.contains($0.id) } }
    }

    func runningTransferIDs() async -> [String] {
        state.withLock { $0.held.map(\.id) }
    }

    private func finish(_ transfer: DownloadTransfer) async {
        guard let downloads = state.withLock({ $0.downloads }) else { return }
        guard let (data, response) = try? await session.data(for: transfer.request) else {
            await downloads.transferFailed(transfer.id)
            return
        }
        let file = FileManager.default.temporaryDirectory.appending(path: "dogear-transfer-\(UUID().uuidString)")
        try? data.write(to: file)
        await downloads.transferFinished(transfer.id, status: (response as? HTTPURLResponse)?.statusCode ?? 0, file: file)
    }
}
