import Foundation

/// A signed-in connection to one Server, persisted in a `TokenStore`.
public struct Session: Codable, Sendable, Equatable {
    public static let testedServerVersion = "v3.5.1"

    public var server: URL
    public var username: String
    public var accessToken: String
    public var refreshToken: String
    public var accessTokenExpiresAt: Date
    /// nil when the Server didn't report a version.
    public var serverVersion: String?
    /// The Server refused the refresh token (expired or revoked). The Session is kept so
    /// the reader can carry on offline with local data intact until they sign in again.
    public var needsSignIn: Bool

    public init(
        server: URL, username: String, accessToken: String, refreshToken: String,
        accessTokenExpiresAt: Date, serverVersion: String? = nil, needsSignIn: Bool = false
    ) {
        self.server = server
        self.username = username
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accessTokenExpiresAt = accessTokenExpiresAt
        self.serverVersion = serverVersion
        self.needsSignIn = needsSignIn
    }

    /// Dogear still works outside the tested version; the reader is just told why things might misbehave.
    public var versionWarning: VersionWarning? {
        guard let serverVersion else { return .unknown }
        return serverVersion == Self.testedServerVersion ? nil : .untested(serverVersion: serverVersion)
    }
}

public enum VersionWarning: Sendable, Equatable {
    case untested(serverVersion: String)
    case unknown
}

public protocol TokenStore: Sendable {
    func load() -> Session?
    func save(_ session: Session) throws
    func clear()
}

/// The password the reader signed in with, kept so an expired sign-in renews itself instead of
/// asking them to sign in again.
public struct SavedLogin: Codable, Sendable, Equatable {
    public var server: URL
    public var username: String
    public var password: String

    public init(server: URL, username: String, password: String) {
        self.server = server
        self.username = username
        self.password = password
    }
}

public protocol PasswordStore: Sendable {
    func load() -> SavedLogin?
    func save(_ login: SavedLogin) throws
    func clear()
}
