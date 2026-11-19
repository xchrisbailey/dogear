import Foundation

/// Signs in to a Server and keeps the resulting Session.
public actor Account {
    private let urlSession: URLSession
    private let tokenStore: any TokenStore
    private let clock: any WallClock

    public private(set) var session: Session?

    public init(urlSession: URLSession = .shared, tokenStore: any TokenStore, clock: any WallClock = SystemClock()) {
        self.urlSession = urlSession
        self.tokenStore = tokenStore
        self.clock = clock
        session = tokenStore.load()
    }

    public func signIn(address: String, username: String, password: String) async throws(SignInError) -> Session {
        let server = try ServerAddress.parse(address)
        let client = GrimmoryClient(server: server, urlSession: urlSession)
        try await client.confirmIsGrimmory()
        let tokens = try await client.login(username: username, password: password)
        // Grimmory doesn't block default-password accounts itself; its web UI forces the
        // change. Without that, the reader would hit confusing failures later.
        if tokens.isDefaultPassword == true { throw .defaultPassword }
        let session = Session(
            server: server,
            username: username,
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            accessTokenExpiresAt: clock.now().addingTimeInterval(tokens.expires),
            serverVersion: await client.serverVersion(accessToken: tokens.accessToken)
        )
        do {
            try tokenStore.save(session)
        } catch {
            throw .couldNotSaveSession
        }
        self.session = session
        return session
    }
}

public enum SignInError: Error, Equatable {
    case invalidAddress
    case insecureAddress
    case couldNotSaveSession
    case unreachable
    case notGrimmory
    case wrongCredentials
    case rateLimited
    case defaultPassword
    case serverChanged
}
