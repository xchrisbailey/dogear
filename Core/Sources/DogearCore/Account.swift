import Foundation

/// Signs in to a Server, keeps the resulting Session, and signs requests with it.
public actor Account {
    private let urlSession: URLSession
    private let tokenStore: any TokenStore
    private let clock: any WallClock
    private var refreshing: Task<Result<Session, RequestError>, Never>?
    private var observers: [UUID: AsyncStream<Session?>.Continuation] = [:]

    public private(set) var session: Session? {
        didSet {
            guard session != oldValue else { return }
            for observer in observers.values { observer.yield(session) }
        }
    }

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

    /// Clears the tokens; the caller warns about a non-empty Outbox first.
    public func signOut() {
        tokenStore.clear()
        refreshing = nil
        session = nil
    }

    /// The current Session, then every change to it (refreshes, needing sign-in, signing out).
    public func sessionUpdates() -> AsyncStream<Session?> {
        let (stream, continuation) = AsyncStream<Session?>.makeStream()
        let id = UUID()
        observers[id] = continuation
        continuation.yield(session)
        continuation.onTermination = { _ in Task { await self.removeObserver(id) } }
        return stream
    }

    private func removeObserver(_ id: UUID) {
        observers[id] = nil
    }

    /// Sends `request` with the access token. A 401 refreshes the tokens once and retries.
    public func send(_ request: URLRequest) async throws(RequestError) -> (status: Int, data: Data) {
        let session = try usableSession()
        let response = try await perform(request, accessToken: session.accessToken)
        guard response.status == 401 else { return response }
        let refreshed = try await refreshedSession(replacing: session.accessToken)
        return try await perform(request, accessToken: refreshed.accessToken)
    }

    private func usableSession() throws(RequestError) -> Session {
        guard let session else { throw .signedOut }
        if session.needsSignIn { throw .needsSignIn }
        return session
    }

    private func perform(_ request: URLRequest, accessToken: String) async throws(RequestError) -> (status: Int, data: Data) {
        var request = request
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await urlSession.data(for: request)
            return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
        } catch {
            throw .unreachable
        }
    }

    /// Single-flight: rotation revokes the refresh token, so a second concurrent refresh
    /// would be refused and sign the reader out.
    private func refreshedSession(replacing staleAccessToken: String) async throws(RequestError) -> Session {
        let session = try usableSession()
        // Another request already refreshed while this one was waiting on the Server.
        if session.accessToken != staleAccessToken { return session }
        if let refreshing { return try await refreshing.value.get() }
        let task = Task { await refresh(session) }
        refreshing = task
        return try await task.value.get()
    }

    private func refresh(_ stale: Session) async -> Result<Session, RequestError> {
        defer { refreshing = nil }
        let client = GrimmoryClient(server: stale.server, urlSession: urlSession)
        let result: Result<GrimmoryClient.LoginTokens, RequestError>
        do {
            result = .success(try await client.refresh(refreshToken: stale.refreshToken))
        } catch {
            result = .failure(error)
        }
        // Signed out, or signed in again, while the refresh was in flight.
        guard self.session?.refreshToken == stale.refreshToken else { return .failure(.signedOut) }

        var updated = stale
        switch result {
        case let .success(tokens):
            updated.accessToken = tokens.accessToken
            updated.refreshToken = tokens.refreshToken
            updated.accessTokenExpiresAt = clock.now().addingTimeInterval(tokens.expires)
        case .failure(.needsSignIn):
            updated.needsSignIn = true
        case let .failure(error):
            // Offline or rate-limited: the refresh token is still good, try again later.
            return .failure(error)
        }
        // If saving fails the in-memory Session still works; a relaunch would then hold a
        // revoked refresh token and ask the reader to sign in again, which is recoverable.
        try? tokenStore.save(updated)
        session = updated
        return updated.needsSignIn ? .failure(.needsSignIn) : .success(updated)
    }
}

public enum RequestError: Error, Equatable {
    /// No Session: the reader never signed in or signed out.
    case signedOut
    /// The Server refused the refresh token; local data stays until the reader signs in again.
    case needsSignIn
    case unreachable
    case rateLimited
    case serverChanged
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
