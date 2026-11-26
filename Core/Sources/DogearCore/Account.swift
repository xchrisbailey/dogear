import Foundation

/// Signs in to a Server, keeps the resulting Session, and signs requests with it.
public actor Account {
    private let urlSession: URLSession
    private let tokenStore: any TokenStore
    /// nil keeps no password: an expired sign-in then always asks the reader.
    private let passwordStore: (any PasswordStore)?
    private let clock: any WallClock
    private var refreshing: Task<Result<Session, RequestError>, Never>?
    private var observers: [UUID: AsyncStream<Session?>.Continuation] = [:]
    private var statusObservers: [UUID: AsyncStream<ServerStatus>.Continuation] = [:]

    /// What the latest requests found, so the app can switch to offline mode or ask for an update.
    public private(set) var serverStatus = ServerStatus() {
        didSet {
            guard serverStatus != oldValue else { return }
            for observer in statusObservers.values { observer.yield(serverStatus) }
        }
    }

    public private(set) var session: Session? {
        didSet {
            guard session != oldValue else { return }
            for observer in observers.values { observer.yield(session) }
        }
    }

    public init(
        urlSession: URLSession = .shared, tokenStore: any TokenStore,
        passwordStore: (any PasswordStore)? = nil, clock: any WallClock = SystemClock()
    ) {
        self.urlSession = urlSession
        self.tokenStore = tokenStore
        self.passwordStore = passwordStore
        self.clock = clock
        session = tokenStore.load()
    }

    public func signIn(address: String, username: String, password: String) async throws(SignInError) -> Session {
        let server = try ServerAddress.parse(address)
        // Signing in again after the sign-in expired. The Outbox, Downloads and cached library
        // belong to that account, so another one starts only after signing out, which warns
        // about what would be lost.
        if let current = session, !ServerAddress.isSame(current.server, server) || current.username != username {
            throw .differentAccount
        }
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
        // Best effort: without it, the reader signs in by hand when the refresh token expires.
        try? passwordStore?.save(SavedLogin(server: server, username: username, password: password))
        self.session = session
        serverStatus = ServerStatus()
        return session
    }

    /// Clears the tokens; the caller warns about a non-empty Outbox first.
    public func signOut() {
        tokenStore.clear()
        passwordStore?.clear()
        refreshing = nil
        session = nil
        serverStatus = ServerStatus()
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

    /// The current `serverStatus`, then every change to it.
    public func serverStatusUpdates() -> AsyncStream<ServerStatus> {
        let (stream, continuation) = AsyncStream<ServerStatus>.makeStream()
        let id = UUID()
        statusObservers[id] = continuation
        continuation.yield(serverStatus)
        continuation.onTermination = { _ in Task { await self.removeStatusObserver(id) } }
        return stream
    }

    private func removeStatusObserver(_ id: UUID) {
        statusObservers[id] = nil
    }

    /// Sends `request` with the access token. A 401 refreshes the tokens once and retries.
    public func send(_ request: URLRequest) async throws(RequestError) -> (status: Int, data: Data) {
        let session = try usableSession()
        let response = try await perform(request, accessToken: session.accessToken)
        guard response.status == 401 else { return response }
        let refreshed = try await refreshedSession(replacing: session.accessToken)
        return try await perform(request, accessToken: refreshed.accessToken)
    }

    /// Sends `request` and decodes its JSON answer. Only an answer Dogear can't decode means the
    /// Server has changed shape.
    public func fetch<T: Decodable & Sendable>(_ type: T.Type, _ request: URLRequest) async throws(RequestError) -> T {
        let data = try await fetchData(request)
        guard let decoded = try? JSONDecoder().decode(type, from: data) else { throw serverChanged() }
        return decoded
    }

    /// Sends `request` and returns the body of a successful answer.
    func fetchData(_ request: URLRequest) async throws(RequestError) -> Data {
        let (status, data) = try await send(request)
        try check(status)
        return data
    }

    /// Sends a change, such as a Position, that the Server must accept.
    public func deliver(_ request: URLRequest) async throws(RequestError) {
        let (status, _) = try await send(request)
        try check(status)
    }

    /// Refusals and missing Books are answers about this request, not signs the Server changed.
    private func check(_ status: Int) throws(RequestError) {
        switch status {
        case 200 ..< 300: return
        case 403: throw .forbidden
        case 404: throw .notFound
        default: throw serverChanged()
        }
    }

    private func serverChanged() -> RequestError {
        serverStatus.hasChanged = true
        return .serverChanged
    }

    /// Asks the Server's public healthcheck whether it can be reached again, for retrying after
    /// working offline. Signed out, there's no Server to ask.
    @discardableResult
    public func checkServer() async -> ServerStatus {
        guard let server = session?.server else { return serverStatus }
        let request = URLRequest(url: server.appending(path: "api/v1/healthcheck"))
        _ = try? await perform(request, accessToken: nil)
        return serverStatus
    }

    /// The access token to sign a request with, for callers that send requests themselves.
    func accessToken() throws(RequestError) -> String {
        try usableSession().accessToken
    }

    /// The access token to retry with after the Server rejected `staleAccessToken`.
    func accessToken(replacing staleAccessToken: String) async throws(RequestError) -> String {
        try await refreshedSession(replacing: staleAccessToken).accessToken
    }

    private func usableSession() throws(RequestError) -> Session {
        guard let session else { throw .signedOut }
        if session.needsSignIn { throw .needsSignIn }
        return session
    }

    private func perform(_ request: URLRequest, accessToken: String?) async throws(RequestError) -> (status: Int, data: Data) {
        do {
            let response = try await performUnobserved(request, accessToken: accessToken)
            serverStatus.isReachable = true
            return response
        } catch .unreachable {
            serverStatus.isReachable = false
            throw .unreachable
        } catch .serverChanged {
            serverStatus.isReachable = true
            throw serverChanged()
        }
    }

    private func performUnobserved(_ request: URLRequest, accessToken: String?) async throws(RequestError) -> (status: Int, data: Data) {
        var request = request
        if let accessToken { request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        let data: Data, response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw .unreachable
        }
        guard let response = response as? HTTPURLResponse else { throw .unreachable }
        switch response.statusCode {
        // Grimmory failing, or a proxy in front of it, such as Tailscale Serve, answering while
        // it's down: worth trying again later, like no connection.
        case 500 ..< 600: throw .unreachable
        case 429: throw .rateLimited
        default: break
        }
        // Grimmory answers paths it doesn't know with its web app, status 200. No API call
        // returns HTML, so the call has moved or gone.
        if response.value(forHTTPHeaderField: "Content-Type")?.lowercased().hasPrefix("text/html") == true {
            throw .serverChanged
        }
        return (response.statusCode, data)
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
            switch await renewWithSavedPassword(stale) {
            case let .success(tokens):
                updated.accessToken = tokens.accessToken
                updated.refreshToken = tokens.refreshToken
                updated.accessTokenExpiresAt = clock.now().addingTimeInterval(tokens.expires)
            case .failure(.needsSignIn):
                updated.needsSignIn = true
            case let .failure(error):
                // Offline or rate-limited: try again on the next request.
                return .failure(error)
            }
            // Signed out, or signed in again by hand, while signing in with the saved password.
            guard self.session?.refreshToken == stale.refreshToken else { return .failure(.signedOut) }
        case let .failure(error):
            if error == .unreachable { serverStatus.isReachable = false }
            if error == .serverChanged { serverStatus.hasChanged = true }
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

extension Account {
    /// Signs in again with the saved password after the Server refused the refresh token.
    /// `.needsSignIn` means the reader must: no password was saved, or it no longer works.
    fileprivate func renewWithSavedPassword(_ stale: Session) async -> Result<GrimmoryClient.LoginTokens, RequestError> {
        guard let login = passwordStore?.load(),
              ServerAddress.isSame(login.server, stale.server), login.username == stale.username
        else { return .failure(.needsSignIn) }
        let client = GrimmoryClient(server: stale.server, urlSession: urlSession)
        do {
            let tokens = try await client.login(username: login.username, password: login.password)
            if tokens.isDefaultPassword == true { return .failure(.needsSignIn) }
            return .success(tokens)
        } catch .unreachable, .serverFailing {
            // A failing Server is like an unreachable one: the saved password is still good.
            serverStatus.isReachable = false
            return .failure(.unreachable)
        } catch .rateLimited {
            return .failure(.rateLimited)
        } catch .wrongCredentials {
            // Changed on the Server: forget it so it isn't tried again, and ask the reader.
            passwordStore?.clear()
            return .failure(.needsSignIn)
        } catch .serverChanged {
            serverStatus.hasChanged = true
            return .failure(.serverChanged)
        } catch {
            return .failure(.needsSignIn)
        }
    }
}

public struct ServerStatus: Sendable, Equatable {
    /// False after a request couldn't reach the Server, such as off the tailnet; the app then
    /// works offline until a request gets through.
    public var isReachable: Bool
    /// The Server answered in a shape Dogear doesn't understand. Stays set until the next
    /// sign-in, since one changed endpoint means others may have changed too.
    public var hasChanged: Bool

    public init(isReachable: Bool = true, hasChanged: Bool = false) {
        self.isReachable = isReachable
        self.hasChanged = hasChanged
    }
}

public enum RequestError: Error, Equatable {
    /// No Session: the reader never signed in or signed out.
    case signedOut
    /// The Server refused the refresh token; local data stays until the reader signs in again.
    case needsSignIn
    case unreachable
    case rateLimited
    /// The account may not do this, such as download without `canDownload` or see a Book
    /// outside its libraries.
    case forbidden
    /// The Book or Book file is no longer on the Server.
    case notFound
    /// The Server answered in a shape Dogear doesn't understand.
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
    /// The Server answered with an error of its own (5xx): it's failing, not changed.
    case serverFailing
    case serverChanged
    /// Signing in again as another account or to another Server while still signed in.
    case differentAccount
}
