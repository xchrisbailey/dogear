import Foundation

/// A signed-in connection to one Server, persisted in a `TokenStore`.
public struct Session: Codable, Sendable, Equatable {
    public static let testedServerVersion = "v3.5.0"

    public var server: URL
    public var username: String
    public var accessToken: String
    public var refreshToken: String
    public var accessTokenExpiresAt: Date
    /// nil when the Server didn't report a version.
    public var serverVersion: String?

    public init(
        server: URL, username: String, accessToken: String, refreshToken: String,
        accessTokenExpiresAt: Date, serverVersion: String? = nil
    ) {
        self.server = server
        self.username = username
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accessTokenExpiresAt = accessTokenExpiresAt
        self.serverVersion = serverVersion
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
