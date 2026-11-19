import Foundation

/// The fake Server's audiobook streams, which take the access token as a `token` query parameter
/// because AVPlayer can't add headers.
extension FakeGrimmory {
    static func audiobookStream(_ request: Request, state: State) -> FakeServer.Reply? {
        let parts = request.path.split(separator: "/").map(String.init)
        guard request.method == "GET", parts.count == 5, parts.starts(with: ["api", "v1", "audiobooks"]), parts[4] == "stream"
        else { return nil }
        guard let token = request.query["token"], state.issued.contains(where: { $0.access == token }), !state.invalid.contains(token)
        else { return fixture("error-401-unauthenticated", status: 401) }
        guard state.library.contains(where: { String($0.id) == parts[3] }) else {
            return fixture("error-404-book", status: 404)
        }
        return .response(status: 200, body: Data("audio-\(parts[3])".utf8), contentType: "audio/mp4")
    }
}
