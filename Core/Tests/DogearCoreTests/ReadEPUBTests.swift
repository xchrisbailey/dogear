import DogearCore
import Foundation
import Testing

/// Opening an EPUB straight from the Server's EPUB file endpoint, as the reader does.
struct ReadEPUBTests {
    let tokenStore = InMemoryTokenStore()
    let server = FakeGrimmory()

    func signedIn() async throws -> Account {
        server.shelve([FakeGrimmory.mobyDick, FakeGrimmory.atomicHabits])
        let account = Account(urlSession: server.session, tokenStore: tokenStore)
        _ = try await account.signIn(address: FakeGrimmory.address, username: "reader", password: "correct horse")
        return account
    }

    /// Fetches `entry` the way the reader's HTTP client does: authorize, send, and on a 401 reauthorize once.
    func fetch(_ entry: String, from epub: ServerEPUB) async throws -> (status: Int, body: Data) {
        let request = URLRequest(url: epub.baseURL.appending(path: entry))
        var (data, response) = try await server.session.data(for: try await epub.authorize(request))
        if (response as? HTTPURLResponse)?.statusCode == 401 {
            let sent = try await epub.authorize(request)
            (data, response) = try await server.session.data(for: try await epub.reauthorize(afterRejecting: sent))
        }
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
    }

    @Test func entriesOfABooksEPUBAreFetchedWithTheAccessToken() async throws {
        let account = try await signedIn()
        let epub = try #require(await ServerEPUB(account: account, bookID: 21))

        let (status, body) = try await fetch("META-INF/container.xml", from: epub)

        #expect(status == 200)
        // Moby-Dick also holds an audiobook, so the EPUB must be picked out explicitly.
        #expect(body == FakeGrimmory.entryBytes(bookID: "21", entry: "META-INF/container.xml"))
        let sent = try #require(server.requests.last)
        #expect(sent.path == "/api/v1/epub/21/file/META-INF/container.xml")
        #expect(sent.headers["Authorization"] == "Bearer access-1")
    }

    @Test func expiredAccessTokenWhileReadingIsRefreshedOnce() async throws {
        let account = try await signedIn()
        let epub = try #require(await ServerEPUB(account: account, bookID: 4))
        server.expireAccessTokens()

        let results = try await withThrowingTaskGroup(of: Int.self) { group in
            for entry in ["OEBPS/content.opf", "OEBPS/toc.xhtml", "OEBPS/xhtml/01.xhtml"] {
                group.addTask { try await fetch(entry, from: epub).status }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }

        #expect(results == [200, 200, 200])
        #expect(server.requests.filter { $0.path == "/api/v1/auth/refresh" }.count == 1)
    }

    @Test func signedOutReaderCantOpenAnEPUB() async throws {
        let account = try await signedIn()
        await account.signOut()

        #expect(await ServerEPUB(account: account, bookID: 4) == nil)
    }
}
