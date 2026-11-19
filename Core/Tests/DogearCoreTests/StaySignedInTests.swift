import DogearCore
import Foundation
import Testing

struct StaySignedInTests {
    let clock = TestClock()
    let tokenStore = InMemoryTokenStore()
    let server = FakeGrimmory()

    func signedInAccount() async throws -> Account {
        let account = Account(urlSession: server.session, tokenStore: tokenStore, clock: clock)
        _ = try await account.signIn(address: FakeGrimmory.address, username: "reader", password: "correct horse")
        return account
    }

    var versionRequest: URLRequest {
        URLRequest(url: URL(string: FakeGrimmory.address)!.appending(path: "api/v1/version"))
    }

    var refreshRequests: [FakeGrimmory.Request] {
        server.requests.filter { $0.path == "/api/v1/auth/refresh" }
    }

    @Test func expiredAccessTokenIsRefreshedAndTheRequestRetried() async throws {
        let account = try await signedInAccount()
        server.expireAccessTokens()

        let (status, _) = try await account.send(versionRequest)

        #expect(status == 200)
        #expect(refreshRequests.map { $0.json?["refreshToken"] as? String } == ["refresh-1"])
        let rotated = try #require(server.issuedTokens.last)
        #expect(server.requests.last?.headers["Authorization"] == "Bearer \(rotated.access)")
        #expect(tokenStore.session?.accessToken == rotated.access)
        #expect(tokenStore.session?.refreshToken == rotated.refresh)
    }

    @Test func concurrent401sShareOneRefresh() async throws {
        let account = try await signedInAccount()
        server.expireAccessTokens()

        let statuses = try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<8 {
                group.addTask { try await account.send(versionRequest).status }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }

        #expect(statuses == Array(repeating: 200, count: 8))
        #expect(refreshRequests.count == 1)
        #expect(await account.session?.needsSignIn == false)
    }

    @Test func eachRefreshUsesTheRotatedRefreshToken() async throws {
        let account = try await signedInAccount()
        server.expireAccessTokens()
        _ = try await account.send(versionRequest)
        server.expireAccessTokens()

        let (status, _) = try await account.send(versionRequest)

        #expect(status == 200)
        #expect(refreshRequests.map { $0.json?["refreshToken"] as? String } == ["refresh-1", "refresh-2"])
    }

    @Test func refusedRefreshAsksToSignInAgainWithoutForgettingTheSession() async throws {
        let account = try await signedInAccount()
        server.expireAccessTokens()
        server.revokeRefreshTokens()

        await #expect(throws: RequestError.needsSignIn) { try await account.send(versionRequest) }

        let session = try #require(await account.session)
        #expect(session.needsSignIn)
        #expect(session.server == URL(string: FakeGrimmory.address))
        #expect(session.username == "reader")
        // Stays that way across a relaunch, and nothing more is sent with dead tokens.
        let relaunched = Account(urlSession: server.session, tokenStore: tokenStore, clock: clock)
        let requestsBefore = server.requests.count
        await #expect(throws: RequestError.needsSignIn) { try await relaunched.send(versionRequest) }
        #expect(server.requests.count == requestsBefore)
        #expect(await relaunched.session?.needsSignIn == true)
    }

    @Test func signingInAgainAfterARefusedRefreshResumes() async throws {
        let account = try await signedInAccount()
        server.expireAccessTokens()
        server.revokeRefreshTokens()
        _ = try? await account.send(versionRequest)

        _ = try await account.signIn(address: FakeGrimmory.address, username: "reader", password: "correct horse")

        #expect(try await account.send(versionRequest).status == 200)
        #expect(tokenStore.session?.needsSignIn == false)
    }

    @Test func signingInAgainAsSomeoneElseIsRefusedUntilSignedOut() async throws {
        let account = try await signedInAccount()
        server.state.withLock { $0.accounts.append(FakeGrimmory.Account(username: "guest", password: "battery staple")) }
        server.expireAccessTokens()
        server.revokeRefreshTokens()
        _ = try? await account.send(versionRequest)

        // The Outbox and Downloads belong to the expired account, so they mustn't carry over.
        await #expect(throws: SignInError.differentAccount) {
            try await account.signIn(address: FakeGrimmory.address, username: "guest", password: "battery staple")
        }
        await #expect(throws: SignInError.differentAccount) {
            try await account.signIn(address: "https://other.example", username: "reader", password: "correct horse")
        }

        #expect(await account.session?.username == "reader")
        #expect(await account.session?.needsSignIn == true)
        #expect(server.requests.filter { $0.path == "/api/v1/auth/login" }.count == 1)
        #expect(SignInError.differentAccount.errorDescription == "This device is signed in to a different Server or account. Sign out first, then sign in.")
    }

    @Test func unreachableServerDuringRefreshKeepsTheReaderSignedIn() async throws {
        let account = try await signedInAccount()
        server.expireAccessTokens()
        server.setKind(.unreachable)

        await #expect(throws: RequestError.unreachable) { try await account.send(versionRequest) }

        #expect(await account.session?.needsSignIn == false)
        server.setKind(.grimmory)
        #expect(try await account.send(versionRequest).status == 200)
    }

    @Test func signingOutForgetsTheTokens() async throws {
        let account = try await signedInAccount()

        await account.signOut()

        #expect(await account.session == nil)
        #expect(tokenStore.session == nil)
        await #expect(throws: RequestError.signedOut) { try await account.send(versionRequest) }
        let relaunched = Account(urlSession: server.session, tokenStore: tokenStore, clock: clock)
        #expect(await relaunched.session == nil)
    }
}
