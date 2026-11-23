import DogearCore
import Foundation
import Testing

struct SignInTests {
    let clock = TestClock()
    let tokenStore = InMemoryTokenStore()

    func account(for server: FakeGrimmory) -> Account {
        Account(urlSession: server.session, tokenStore: tokenStore, clock: clock)
    }

    @Test func signingInStoresTheIssuedTokens() async throws {
        let server = FakeGrimmory()

        let session = try await account(for: server).signIn(
            address: FakeGrimmory.address, username: "reader", password: "correct horse"
        )

        let issued = try #require(server.issuedTokens.last)
        #expect(tokenStore.session == session)
        #expect(session.accessToken == issued.access)
        #expect(session.refreshToken == issued.refresh)
        #expect(session.server == URL(string: FakeGrimmory.address))
        #expect(session.accessTokenExpiresAt == clock.now().addingTimeInterval(7200))
    }

    @Test func plainHTTPAddressIsRefusedBeforeAnythingIsSent() async {
        let server = FakeGrimmory()

        await #expect(throws: SignInError.insecureAddress) {
            try await account(for: server).signIn(
                address: "http://grimmory.example", username: "reader", password: "correct horse"
            )
        }
        #expect(server.requests.isEmpty)
        #expect(tokenStore.session == nil)
    }

    @Test(arguments: [
        "http://100.63.255.1",
        "http://100.128.0.1",
        "http://192.168.1.10:6060",
        "http://grimmory.example.ts.net.evil.example",
    ])
    func plainHTTPOffTailscaleIsRefused(address: String) async {
        let server = FakeGrimmory()

        await #expect(throws: SignInError.insecureAddress) {
            try await account(for: server).signIn(address: address, username: "reader", password: "correct horse")
        }
        #expect(server.requests.isEmpty)
    }

    /// WireGuard already encrypts a tailnet, and a Server there usually answers plain HTTP.
    @Test(arguments: [
        ("http://books.tail1234.ts.net:6060", "http://books.tail1234.ts.net:6060"),
        ("http://100.101.102.103:6060", "http://100.101.102.103:6060"),
        ("http://[fd7a:115c:a1e0::1]:6060", "http://[fd7a:115c:a1e0::1]:6060"),
        ("http://grimmory:6060", "http://grimmory:6060"),
        ("books.tail1234.ts.net:6060", "http://books.tail1234.ts.net:6060"),
        ("100.101.102.103:6060/", "http://100.101.102.103:6060"),
        ("https://books.tail1234.ts.net", "https://books.tail1234.ts.net"),
        ("grimmory.example", "https://grimmory.example"),
    ])
    func tailscaleAddressMaySkipHTTPS(typed: String, expected: String) async throws {
        let server = FakeGrimmory()

        let session = try await account(for: server).signIn(address: typed, username: "reader", password: "correct horse")

        #expect(session.server == URL(string: expected))
    }

    @Test(arguments: [
        (FakeGrimmory.Kind.unreachable, "correct horse", SignInError.unreachable),
        (.notGrimmory, "correct horse", .notGrimmory),
        (.grimmory, "wrong", .wrongCredentials),
    ])
    func failedSignInSaysWhy(kind: FakeGrimmory.Kind, password: String, expected: SignInError) async {
        let server = FakeGrimmory(kind: kind)

        await #expect(throws: expected) {
            try await account(for: server).signIn(
                address: FakeGrimmory.address, username: "reader", password: password
            )
        }
        #expect(tokenStore.session == nil)
    }

    @Test func notGrimmoryIsDetectedBeforeCredentialsAreSent() async {
        let server = FakeGrimmory(kind: .notGrimmory)

        _ = try? await account(for: server).signIn(
            address: FakeGrimmory.address, username: "reader", password: "correct horse"
        )

        #expect(!server.requests.contains { $0.path == "/api/v1/auth/login" })
    }

    @Test func accountWithDefaultPasswordIsToldToChangeItFirst() async {
        let server = FakeGrimmory(accounts: [.init(username: "admin", password: "admin123", isDefaultPassword: true)])
        let account = account(for: server)

        await #expect(throws: SignInError.defaultPassword) {
            try await account.signIn(address: FakeGrimmory.address, username: "admin", password: "admin123")
        }
        #expect(tokenStore.session == nil)
        #expect(await account.session == nil)
    }

    @Test func testedServerVersionSignsInWithoutWarning() async throws {
        let session = try await account(for: FakeGrimmory(version: "v3.5.0")).signIn(
            address: FakeGrimmory.address, username: "reader", password: "correct horse"
        )

        #expect(session.serverVersion == "v3.5.0")
        #expect(session.versionWarning == nil)
    }

    @Test func untestedServerVersionWarnsButStillSignsIn() async throws {
        let server = FakeGrimmory(version: "v3.6.0")

        let session = try await account(for: server).signIn(
            address: FakeGrimmory.address, username: "reader", password: "correct horse"
        )

        #expect(session.versionWarning == .untested(serverVersion: "v3.6.0"))
        #expect(tokenStore.session == session)
        // The version endpoint needs sign-in, so it must carry the new access token.
        let versionRequest = try #require(server.requests.first { $0.path == "/api/v1/version" })
        #expect(versionRequest.headers["Authorization"] == "Bearer \(session.accessToken)")
    }

    @Test func relaunchingKeepsTheReaderSignedIn() async throws {
        let server = FakeGrimmory()
        let signedIn = try await account(for: server).signIn(
            address: FakeGrimmory.address, username: "reader", password: "correct horse"
        )
        let requestsBeforeRelaunch = server.requests.count

        let relaunched = account(for: server)

        #expect(await relaunched.session == signedIn)
        #expect(server.requests.count == requestsBeforeRelaunch)
    }

    @Test func addressWithoutSchemeIsTreatedAsHTTPS() async throws {
        let session = try await account(for: FakeGrimmory()).signIn(
            address: "  grimmory.example/ ", username: "reader", password: "correct horse"
        )

        #expect(session.server == URL(string: "https://grimmory.example"))
    }
}
