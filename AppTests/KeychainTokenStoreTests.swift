import DogearCore
import Foundation
import Testing

/// Seam 2: the Keychain only works with the entitlements the app is signed with, so this runs
/// hosted in the app as built by the documented simulator command.
struct KeychainTokenStoreTests {
    @Test
    func savedSessionLoadsBack() throws {
        let store = KeychainTokenStore(service: "Dogear.tests.\(UUID().uuidString)")
        defer { store.clear() }
        let session = Session(
            server: try #require(URL(string: "https://books.example")),
            username: "reader",
            accessToken: "access",
            refreshToken: "refresh",
            accessTokenExpiresAt: Date(timeIntervalSince1970: 1_800_000_000),
            serverVersion: nil
        )

        try store.save(session)

        #expect(store.load() == session)
    }
}
