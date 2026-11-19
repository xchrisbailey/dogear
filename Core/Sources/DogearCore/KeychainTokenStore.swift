import Foundation
import Security

/// Keeps the Session, tokens included, in the Keychain as one item.
/// Not covered by seam 1: the Keychain needs entitlements an unsigned `swift test` binary lacks.
public struct KeychainTokenStore: TokenStore {
    private let service: String

    public init(service: String = "Dogear.session") {
        self.service = service
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
    }

    public func load() -> Session? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    public func save(_ session: Session) throws {
        let data = try JSONEncoder().encode(session)
        clear()
        var item = query
        item[kSecValueData as String] = data
        // Readable after first unlock so background work (audio, Outbox flushes) can still sign requests.
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    public func clear() {
        SecItemDelete(query as CFDictionary)
    }
}

public struct KeychainError: Error {
    public let status: OSStatus
}
