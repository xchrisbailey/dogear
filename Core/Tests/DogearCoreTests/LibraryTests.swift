import DogearCore
import Foundation
import Testing

struct LibraryTests {
    let tokenStore = InMemoryTokenStore()
    let storeURL = FileManager.default.temporaryDirectory
        .appending(path: "dogear-library-\(UUID().uuidString)")
        .appending(path: "Library.store")

    /// Signs in to `server`, then opens the Library as the app would after launch.
    func signedInLibrary(on server: FakeGrimmory) async throws -> Library {
        let account = Account(urlSession: server.session, tokenStore: tokenStore)
        _ = try await account.signIn(address: FakeGrimmory.address, username: "reader", password: "correct horse")
        return try library(on: server)
    }

    /// A Library using whatever Session is already stored, like a relaunch.
    func library(on server: FakeGrimmory) throws -> Library {
        Library(
            account: Account(urlSession: server.session, tokenStore: tokenStore),
            store: try LibraryStore(url: storeURL)
        )
    }

    @Test func bookWithSeveralBookFilesAppearsOnceWithItsFormats() async throws {
        let server = FakeGrimmory()
        server.shelve([FakeGrimmory.mobyDick, FakeGrimmory.atomicHabits])
        let library = try await signedInLibrary(on: server)

        let books = try await library.refresh()

        #expect(books.map(\.title) == ["Moby-Dick; or, The Whale", "Atomic Habits: Tiny Changes, Remarkable Results"])
        let mobyDick = try #require(books.first)
        #expect(mobyDick.authors == ["Herman Melville"])
        // The supplementary PDF isn't a Book file, so it isn't listed.
        #expect(mobyDick.files.map(\.id) == [31, 32, 33])
        #expect(mobyDick.formats == [.epub, .audiobook, .mobi])
    }

    @Test func bookFilesDogearCantOpenAreMarkedNotSupported() async throws {
        var opusSingle = FakeGrimmory.projectHailMary
        opusSingle.replacing = ["m4b": "opus"]
        var opusFolder = FakeGrimmory.slaughterhouseFive
        opusFolder.replacing = [".MP3": ".opus"]
        let server = FakeGrimmory()
        server.shelve([FakeGrimmory.mobyDick, FakeGrimmory.allSystemsRed, opusSingle, opusFolder])

        let books = try await signedInLibrary(on: server).refresh()

        let supported = books.map { $0.files.map(\.isSupported) }
        #expect(supported == [[true, true, false], [false], [false], [false]])
    }

    @Test func mp3AndM4BAudiobooksAreSupported() async throws {
        let server = FakeGrimmory()
        server.shelve([FakeGrimmory.projectHailMary, FakeGrimmory.slaughterhouseFive])

        let books = try await signedInLibrary(on: server).refresh()

        #expect(books.flatMap(\.files).map(\.isSupported) == [true, true])
        #expect(books.flatMap(\.formats) == [.audiobook, .audiobook])
    }

    @Test func cachedBooksAreShownAfterRelaunchWhenTheServerIsUnreachable() async throws {
        let server = FakeGrimmory()
        server.shelve([FakeGrimmory.mobyDick, FakeGrimmory.projectHailMary])
        let online = try await signedInLibrary(on: server).refresh()

        let offline = try library(on: FakeGrimmory(kind: .unreachable))

        await #expect(throws: RequestError.unreachable) { try await offline.refresh() }
        #expect(await offline.cachedBooks() == online)
    }

    @Test func refreshingPicksUpBooksAddedAndRemovedOnTheServer() async throws {
        let server = FakeGrimmory()
        server.shelve([FakeGrimmory.atomicHabits])
        let library = try await signedInLibrary(on: server)
        _ = try await library.refresh()

        server.shelve([FakeGrimmory.allSystemsRed, FakeGrimmory.projectHailMary])
        let books = try await library.refresh()

        #expect(books.map(\.id) == [14, 5])
        #expect(await library.cachedBooks().map(\.id) == [14, 5])
    }

    @Test func oneBookFailingDoesNotHoldUpTheRestOfTheLibrary() async throws {
        let server = FakeGrimmory()
        server.shelve([FakeGrimmory.mobyDick, FakeGrimmory.atomicHabits, FakeGrimmory.projectHailMary])
        let library = try await signedInLibrary(on: server)
        let before = try await library.refresh()
        // Moby-Dick is deleted between the list and its detail; Atomic Habits' detail comes
        // back in a shape Dogear can't read.
        server.answer("GET", "/api/v1/app/books/21", with: FakeGrimmory.fixture("error-404-book", status: 404))
        server.answer("GET", "/api/v1/app/books/4", with: .response(status: 200, body: Data(#"{"unexpected":true}"#.utf8)))

        let books = try await library.refresh()

        #expect(books.map(\.id) == [4, 5])
        #expect(books.first == before[1])
        #expect(await library.cachedBooks().map(\.id) == [4, 5])
    }

    @Test func expiredAccessTokenDuringRefreshIsRenewedOnce() async throws {
        let server = FakeGrimmory()
        server.shelve([FakeGrimmory.mobyDick, FakeGrimmory.atomicHabits, FakeGrimmory.projectHailMary])
        let library = try await signedInLibrary(on: server)
        server.expireAccessTokens()

        let books = try await library.refresh()

        #expect(books.map(\.id) == [21, 4, 5])
        #expect(server.requests.filter { $0.path == "/api/v1/auth/refresh" }.count == 1)
    }

    @Test func audiobookUsesItsOwnCover() async throws {
        let server = FakeGrimmory()
        server.shelve([FakeGrimmory.projectHailMary, FakeGrimmory.mobyDick])
        let library = try await signedInLibrary(on: server)
        let books = try await library.refresh()

        let images = await [library.image(for: try #require(books[0].cover)), library.image(for: try #require(books[1].cover))]

        #expect(images == [
            FakeGrimmory.coverBytes(bookID: 5, kind: "audiobook-thumbnail"),
            FakeGrimmory.coverBytes(bookID: 21, kind: "thumbnail"),
        ])
        #expect(books[1].audiobookCover == Cover(bookID: 21, kind: .audiobook, updatedOn: "2026-11-10T09:05:00Z"))
    }

    @Test func coversAreShownOfflineOnceFetched() async throws {
        let server = FakeGrimmory()
        server.shelve([FakeGrimmory.atomicHabits])
        let books = try await signedInLibrary(on: server).refresh()
        let cover = try #require(books.first?.cover)
        _ = try await library(on: server).image(for: cover)

        let offline = try library(on: FakeGrimmory(kind: .unreachable))

        #expect(await offline.image(for: cover) == FakeGrimmory.coverBytes(bookID: 4, kind: "thumbnail"))
    }

    @Test func forgettingTheLibraryLeavesNothingOffline() async throws {
        let server = FakeGrimmory()
        server.shelve([FakeGrimmory.atomicHabits])
        let library = try await signedInLibrary(on: server)
        let cover = try #require(try await library.refresh().first?.cover)
        _ = await library.image(for: cover)

        await library.forget()

        let offline = try self.library(on: FakeGrimmory(kind: .unreachable))
        #expect(await offline.cachedBooks().isEmpty)
        #expect(await offline.image(for: cover) == nil)
    }
}
