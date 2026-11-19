import DogearCore
import Foundation
import Testing

struct LibraryNavigationTests {
    let tokenStore = InMemoryTokenStore()
    let storeURL = FileManager.default.temporaryDirectory
        .appending(path: "dogear-navigation-\(UUID().uuidString)")
        .appending(path: "Library.store")

    func signedInLibrary(on server: FakeGrimmory) async throws -> Library {
        let account = Account(urlSession: server.session, tokenStore: tokenStore)
        _ = try await account.signIn(address: FakeGrimmory.address, username: "reader", password: "correct horse")
        return try library(on: server)
    }

    func library(on server: FakeGrimmory) throws -> Library {
        Library(
            account: Account(urlSession: server.session, tokenStore: tokenStore),
            store: try LibraryStore(url: storeURL)
        )
    }

    /// Ebook library (2): Atomic Habits, All Systems Red, Moby-Dick. Audiobooks library (1): the other two.
    static let everything = [
        FakeGrimmory.atomicHabits, FakeGrimmory.projectHailMary, FakeGrimmory.allSystemsRed,
        FakeGrimmory.slaughterhouseFive, FakeGrimmory.mobyDick,
    ]

    @Test func booksAreBrowsedByGrimmoryLibrary() async throws {
        let server = FakeGrimmory()
        server.shelve(Self.everything)
        let library = try await signedInLibrary(on: server)

        _ = try await library.refresh()

        #expect(await library.navigation().libraries == [
            ServerLibrary(id: 1, name: "Audiobooks"), ServerLibrary(id: 2, name: "Ebook"),
        ])
        #expect(await library.books(in: .library(2)).map(\.id) == [4, 14, 21])
        #expect(await library.books(in: .library(1)).map(\.id) == [5, 6])
        #expect(await library.books(in: .everything).map(\.id) == [4, 5, 14, 6, 21])
        // Grimmory's app libraries endpoint fails for non-admins, so it's never relied on.
        #expect(!server.requests.contains { $0.path == "/api/v1/app/libraries" })
    }

    @Test func booksAreBrowsedByShelf() async throws {
        let server = FakeGrimmory()
        server.shelve(Self.everything)
        server.setShelves([
            .init(id: 2, name: "Favorites", bookIDs: [21, 5]),
            .init(id: 3, name: "To read", bookIDs: []),
        ])
        let library = try await signedInLibrary(on: server)

        _ = try await library.refresh()

        #expect(await library.navigation().shelves == [Shelf(id: 2, name: "Favorites"), Shelf(id: 3, name: "To read")])
        #expect(await library.books(in: .shelf(2)).map(\.id) == [5, 21])
        #expect(await library.books(in: .shelf(3)).isEmpty)
    }

    @Test func booksAreSearchedByTitleAndAuthor() async throws {
        let server = FakeGrimmory()
        server.shelve(Self.everything)
        let library = try await signedInLibrary(on: server)
        _ = try await library.refresh()

        #expect(await library.books(matching: "hail mary").map(\.title) == ["Project Hail Mary"])
        #expect(await library.books(matching: "  MELVILLE ").map(\.title) == ["Moby-Dick; or, The Whale"])
        // Every word has to match, in the title or an author.
        #expect(await library.books(matching: "whale herman").map(\.id) == [21])
        #expect(await library.books(matching: "whale clear").isEmpty)
        #expect(await library.books(matching: "").count == 5)
        #expect(await library.books(in: .library(1), matching: "red").isEmpty)
    }

    @Test func booksAreFilteredBetweenEbooksAndAudiobooks() async throws {
        let server = FakeGrimmory()
        server.shelve(Self.everything)
        let library = try await signedInLibrary(on: server)
        _ = try await library.refresh()

        // Moby-Dick has an EPUB and an audiobook, so it's in both.
        #expect(await library.books(showing: .ebooks).map(\.id) == [4, 14, 21])
        #expect(await library.books(showing: .audiobooks).map(\.id) == [5, 6, 21])
        #expect(await library.books(showing: .all).count == 5)
        #expect(await library.books(in: .library(2), matching: "moby", showing: .audiobooks).map(\.id) == [21])
    }

    @Test func librariesShelvesSearchAndFilterWorkOfflineAfterRelaunch() async throws {
        let server = FakeGrimmory()
        server.shelve(Self.everything)
        server.setShelves([.init(id: 2, name: "Favorites", bookIDs: [21, 4])])
        let online = try await signedInLibrary(on: server)
        _ = try await online.refresh()
        let navigation = await online.navigation()

        let offline = try library(on: FakeGrimmory(kind: .unreachable))
        await #expect(throws: RequestError.unreachable) { try await offline.refresh() }

        #expect(await offline.navigation() == navigation)
        #expect(await offline.books(in: .library(1)).map(\.id) == [5, 6])
        #expect(await offline.books(in: .shelf(2), matching: "habits", showing: .ebooks).map(\.id) == [4])

        await offline.forget()
        #expect(await offline.navigation() == Navigation())
    }
}
