import DogearCore
import Foundation
import Synchronization

/// A stand-in Grimmory Server built from real v3.5.0 responses (`Fixtures/`).
/// Holds the state a real Server would (accounts, issued tokens) and records
/// every request so tests can assert on what Dogear sent.
final class FakeGrimmory: Sendable {
    enum Kind: Sendable {
        case grimmory
        /// Some other web server at the address: everything is a 200 HTML page.
        case notGrimmory
        /// Nothing answers at the address.
        case unreachable
    }

    struct Account: Sendable {
        var username: String
        var password: String
        var isDefaultPassword = false
    }

    struct Request: Sendable {
        var method: String
        var path: String
        var headers: [String: String]
        var json: [String: any Sendable]?
        var query: [String: String] = [:]
    }

    struct Tokens: Sendable, Equatable {
        var access: String
        var refresh: String
    }

    static let address = "https://grimmory.example"
    static let reader = Account(username: "reader", password: "correct horse")

    struct State {
        var kind: Kind
        var version: String
        var accounts: [Account]
        var issued: [Tokens] = []
        /// Access tokens past their lifetime, and refresh tokens rotated away or revoked.
        var invalid: Set<String> = []
        var requests: [Request] = []
        var library: [ShelvedBook] = []
        var shelves: [Shelf] = []
        /// `app-progress-*` fixture names by Book id.
        var sharedPositions: [Int: String] = [:]
        /// What `app/users/me` reports; the fixture's reader may download.
        var canDownload = true
        var isAdmin = false
        /// Continue Reading and Continue Listening rows by list name.
        var continueRows: [String: [(bookID: Int, lastReadTime: String)]] = [:]
        /// Replies that replace the Server's own for paths starting with a prefix.
        var overrides: [(method: String, pathPrefix: String, reply: FakeServer.Reply)] = []
    }

    let state: Mutex<State>

    init(kind: Kind = .grimmory, version: String = Session.testedServerVersion, accounts: [Account] = [FakeGrimmory.reader]) {
        state = Mutex(State(kind: kind, version: version, accounts: accounts))
    }

    /// A URLSession whose requests are answered by this fake.
    var session: URLSession {
        FakeServer.session { [self] request, body in handle(request, body: body) }
    }

    var requests: [Request] { state.withLock { $0.requests } }
    var issuedTokens: [Tokens] { state.withLock { $0.issued } }

    /// Every access token issued so far stops working, as after its 2 h lifetime.
    func expireAccessTokens() {
        state.withLock { state in state.invalid.formUnion(state.issued.map(\.access)) }
    }

    /// Every refresh token issued so far is refused, as when expired or revoked.
    func revokeRefreshTokens() {
        state.withLock { state in state.invalid.formUnion(state.issued.map(\.refresh)) }
    }

    func setKind(_ kind: Kind) {
        state.withLock { $0.kind = kind }
    }

    /// Answers `method` requests under `pathPrefix` with `reply` instead, as a changed or
    /// broken Server would.
    func answer(_ method: String, _ pathPrefix: String, with reply: FakeServer.Reply) {
        state.withLock { $0.overrides.append((method, pathPrefix, reply)) }
    }

    /// The Server answers for itself again.
    func clearAnswers() {
        state.withLock { $0.overrides = [] }
    }

    private func handle(_ request: URLRequest, body: Data?) -> FakeServer.Reply {
        state.withLock { state in
            let recorded = Request(
                method: request.httpMethod ?? "GET",
                path: request.url?.path ?? "",
                headers: request.allHTTPHeaderFields ?? [:],
                json: body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: any Sendable] },
                query: Self.query(of: request)
            )
            state.requests.append(recorded)

            switch state.kind {
            case .unreachable: return .failure(.cannotConnectToHost)
            case .notGrimmory: return Self.spaPage
            case .grimmory: break
            }
            if let override = state.overrides.last(where: { $0.method == recorded.method && recorded.path.hasPrefix($0.pathPrefix) }) {
                return override.reply
            }

            switch (recorded.method, recorded.path) {
            case ("GET", "/api/v1/healthcheck"):
                return Self.fixture("healthcheck", replacing: ["v3.5.0": state.version])
            case ("POST", "/api/v1/auth/login"):
                return Self.login(recorded.json, state: &state)
            case ("POST", "/api/v1/auth/refresh"):
                return Self.refresh(recorded.json, state: &state)
            case ("GET", "/api/v1/version"):
                guard Self.isAuthorized(recorded, state: state) else {
                    return Self.fixture("error-401-unauthenticated", status: 401)
                }
                return Self.fixture("version", replacing: ["v3.5.0": state.version])
            default:
                // Grimmory answers unknown paths with its web app, not a 404.
                return Self.progress(recorded, state: state) ?? Self.download(recorded, state: state) ?? Self.continueList(recorded, state: state) ?? Self.audiobookStream(recorded, state: state) ?? Self.library(recorded, state: state) ?? Self.epub(recorded, state: state)
                    ?? Self.content(recorded, state: state) ?? Self.spaPage
            }
        }
    }

    private static func query(of request: URLRequest) -> [String: String] {
        let items = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, last in last })
    }

    private static func login(_ json: [String: any Sendable]?, state: inout State) -> FakeServer.Reply {
        let username = json?["username"] as? String
        let password = json?["password"] as? String
        guard let account = state.accounts.first(where: { $0.username == username && $0.password == password }) else {
            return fixture("login-wrong-password", status: 401)
        }
        let tokens = issueTokens(state: &state)
        return fixture(
            account.isDefaultPassword ? "login-default-password" : "login-success",
            replacing: ["<ACCESS_TOKEN>": tokens.access, "<REFRESH_TOKEN>": tokens.refresh]
        )
    }

    private static func refresh(_ json: [String: any Sendable]?, state: inout State) -> FakeServer.Reply {
        guard let token = json?["refreshToken"] as? String,
              state.issued.contains(where: { $0.refresh == token }), !state.invalid.contains(token)
        else { return fixture("refresh-rejected", status: 401) }
        // Rotation: the presented refresh token is revoked once a new one is issued.
        state.invalid.insert(token)
        let tokens = issueTokens(state: &state)
        return fixture("refresh-success", replacing: ["<ACCESS_TOKEN_2>": tokens.access, "<REFRESH_TOKEN_2>": tokens.refresh])
    }

    private static func issueTokens(state: inout State) -> Tokens {
        let n = state.issued.count + 1
        let tokens = Tokens(access: "access-\(n)", refresh: "refresh-\(n)")
        state.issued.append(tokens)
        return tokens
    }

    static func isAuthorized(_ request: Request, state: State) -> Bool {
        guard let header = request.headers["Authorization"], header.hasPrefix("Bearer ") else { return false }
        let token = String(header.dropFirst("Bearer ".count))
        return state.issued.contains { $0.access == token } && !state.invalid.contains(token)
    }

    static let spaPage = FakeServer.Reply.response(
        status: 200, body: Data("<!doctype html><html><body>app</body></html>".utf8), contentType: "text/html"
    )

    static func fixture(_ name: String, status: Int = 200, replacing: [String: String] = [:]) -> FakeServer.Reply {
        let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
        var text = try! String(contentsOf: url, encoding: .utf8)
        for (placeholder, value) in replacing {
            text = text.replacingOccurrences(of: placeholder, with: value)
        }
        return .response(status: status, body: Data(text.utf8))
    }
}
