import Foundation

/// The fake Server's audiobook streams, which take the access token as a `token` query parameter
/// because AVPlayer can't add headers: the whole Book file, or one Track of a folder audiobook.
extension FakeGrimmory {
    static func audiobookStream(_ request: Request, state: State) -> FakeServer.Reply? {
        let parts = request.path.split(separator: "/").map(String.init)
        guard request.method == "GET", parts.starts(with: ["api", "v1", "audiobooks"]), parts.last == "stream",
              parts.count == 5 || (parts.count == 7 && parts[4] == "track")
        else { return nil }
        // Header auth works here too, as for any other endpoint.
        let headerToken = request.headers["Authorization"].map { String($0.dropFirst("Bearer ".count)) }
        guard let token = request.query["token"] ?? headerToken, state.issued.contains(where: { $0.access == token }), !state.invalid.contains(token)
        else { return fixture("error-401-unauthenticated", status: 401) }
        guard let book = state.library.first(where: { String($0.id) == parts[3] }) else {
            return fixture("error-404-book", status: 404)
        }
        guard parts.count == 7 else {
            return .response(status: 200, body: Data("audio-\(parts[3])".utf8), contentType: "audio/mp4")
        }
        let tracks = book.audiobookInfo.map { json($0, replacing: book.replacing)["tracks"] as? [[String: Any]] ?? [] } ?? []
        guard tracks.contains(where: { String(describing: $0["index"] ?? "") == parts[5] }) else {
            return fixture("error-404-track", status: 404)
        }
        return .response(status: 200, body: Data("audio-\(parts[3])-track-\(parts[5])".utf8), contentType: "audio/mpeg")
    }
}
