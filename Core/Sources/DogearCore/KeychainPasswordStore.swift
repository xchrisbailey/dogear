import Foundation
import Security

/// Keeps the reader's Grimmory password in the Keychain, apart from the Session, so an expired
/// sign-in can renew itself. Device-only and never synced, like the tokens.
/// Not covered by seam 1: the Keychain needs entitlements an unsigned `swift test` binary lacks.
public struct KeychainPasswordStore: PasswordStore {
    private let service: String

    public init(service: String = "Dogear.login") {
        self.service = service
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
    }

    public func load() -> SavedLogin? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return try? JSONDecoder().decode(SavedLogin.self, from: data)
    }

    public func save(_ login: SavedLogin) throws {
        let data = try JSONEncoder().encode(login)
        clear()
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccount as String] = login.username
        item[kSecAttrLabel as String] = "Dogear: \(login.server.host() ?? login.server.absoluteString)"
        // Readable after first unlock so a background refresh can renew the sign-in too.
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    public func clear() {
        SecItemDelete(query as CFDictionary)
    }
}
