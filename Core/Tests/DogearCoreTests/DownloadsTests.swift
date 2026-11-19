import DogearCore
import Foundation
import Testing

/// Downloads: Book files kept on the device, only for readers the Server lets download.
struct DownloadsTests {
    let server = FakeGrimmory()
    /// With its audiobook's info, borrowed from another Book's.
    static let mobyDick = FakeGrimmory.ShelvedBook(
        detail: "book-detail-multi-file", audiobookInfo: "audiobook-info-single", replacing: ["\"bookFileId\": 5": "\"bookFileId\": 32"]
    )

    func signedIn() async throws -> Account {
        server.shelve([FakeGrimmory.atomicHabits, FakeGrimmory.slaughterhouseFive, Self.mobyDick])
        let account = Account(urlSession: server.session, tokenStore: InMemoryTokenStore())
        _ = try await account.signIn(address: FakeGrimmory.address, username: "reader", password: "correct horse")
        return account
    }

    static func directory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "dogear-downloads-\(UUID().uuidString)")
    }

    func downloads(_ account: Account, in directory: URL = directory()) async throws -> (Downloads, FakeTransport) {
        let transport = FakeTransport(server: server)
        let downloads = try Downloads(account: account, directory: directory, transport: transport)
        transport.attach(downloads)
        return (downloads, transport)
    }

    func book(_ id: Int, _ account: Account) async throws -> Book {
        try #require(try await Library(account: account, store: LibraryStore(url: Self.directory().appending(path: "Library.store"))).refresh().first { $0.id == id })
    }

    @Test(arguments: [
        (canDownload: false, isAdmin: false, allowed: false),
        (canDownload: true, isAdmin: false, allowed: true),
        // Grimmory lets admins download whatever their permissions say.
        (canDownload: false, isAdmin: true, allowed: true),
    ])
    func downloadingFollowsTheReadersPermission(canDownload: Bool, isAdmin: Bool, allowed: Bool) async throws {
        server.setPermissions(canDownload: canDownload, isAdmin: isAdmin)
        let account = try await signedIn()
        let (downloads, _) = try await downloads(account)
        let mobyDick = try await book(21, account)
        // The audiobook isn't the primary file, and Grimmory doesn't check the permission for those.
        let audiobook = try #require(mobyDick.files.first { $0.format == .audiobook })

        await downloads.checkPermission()

        #expect(await downloads.list.canDownload == allowed)
        if allowed {
            try await downloads.download(audiobook, of: mobyDick)
            #expect(await downloads.list.download(bookFileID: audiobook.id)?.state == .finished)
        } else {
            await #expect(throws: DownloadError.notAllowed) { try await downloads.download(audiobook, of: mobyDick) }
            #expect(!server.requests.contains { $0.path.hasSuffix("/download") })
            #expect(await downloads.list.downloads.isEmpty)
        }
    }

    @Test func downloadedEPUBOpensFromTheDevice() async throws {
        let account = try await signedIn()
        let (downloads, transport) = try await downloads(account)
        await downloads.checkPermission()
        let atomicHabits = try await book(4, account)
        let epub = try #require(atomicHabits.files.first)
        transport.hold()

        try await downloads.download(epub, of: atomicHabits)

        // Until it has arrived, the EPUB opens from the Server.
        #expect(await downloads.list.download(bookFileID: 4)?.state == .downloading(progress: 0))
        #expect(await downloads.downloaded(epub) == nil)
        // Queued transfers can outlive the access token.
        server.expireAccessTokens()
        await transport.release()

        guard case let .epub(file)? = await downloads.downloaded(epub) else {
            Issue.record("not downloaded")
            return
        }
        #expect(try Data(contentsOf: file) == FakeGrimmory.fileBytes(bookID: 4, fileID: 4))
        #expect(file.pathExtension == "epub")
        #expect(transport.started.map(\.request.url?.path) == ["/api/v1/books/4/download", "/api/v1/books/4/download"])
        #expect(transport.started.last?.request.value(forHTTPHeaderField: "Authorization") == "Bearer access-2")
    }

    @Test func downloadedFolderAudiobookPlaysTrackByTrackOfflineAfterARelaunch() async throws {
        let account = try await signedIn()
        let directory = Self.directory()
        let (downloads, _) = try await downloads(account, in: directory)
        await downloads.checkPermission()
        let slaughterhouseFive = try await book(6, account)
        let audiobook = try #require(slaughterhouseFive.files.first)
        try await downloads.download(audiobook, of: slaughterhouseFive)

        server.setKind(.unreachable)
        let (relaunched, _) = try await self.downloads(account, in: directory)

        #expect(await relaunched.list.canDownload)
        guard case let .audiobook(downloaded)? = await relaunched.downloaded(audiobook) else {
            Issue.record("not downloaded")
            return
        }
        let info = try await downloaded.info()
        #expect(info.bookFileID == 6)
        #expect(info.tracks.map(\.index) == [0, 1, 2, 80])
        let stream = try #require(await downloaded.streamUpdates().first { _ in true })
        #expect(stream.track(80).isFileURL)
        #expect(stream.track(80).pathExtension == "mp3")
        #expect(try Data(contentsOf: stream.track(80)) == Data("audio-6-track-80".utf8))
    }

    @Test func storageIsCountedPerBookAndRemovedOnlyByTheReader() async throws {
        let account = try await signedIn()
        let (downloads, transport) = try await downloads(account)
        await downloads.checkPermission()
        let mobyDick = try await book(21, account)
        let epub = try #require(mobyDick.files.first { $0.format == .epub })
        let audiobook = try #require(mobyDick.files.first { $0.format == .audiobook })
        let atomicHabits = try await book(4, account)
        try await downloads.download(epub, of: mobyDick)
        try await downloads.download(audiobook, of: mobyDick)
        transport.hold()
        try await downloads.download(try #require(atomicHabits.files.first), of: atomicHabits)

        let list = await downloads.list
        // "file-21-31" and "file-21-32".
        #expect(list.bytes(ofBook: 21) == 20)
        #expect(list.bytes(ofBook: 4) == 0)
        #expect(list.totalBytes == 20)
        // A Book that leaves the library keeps its Downloads until the reader removes them.
        server.shelve([])
        _ = try await Library(account: account, store: LibraryStore(url: Self.directory().appending(path: "Library.store"))).refresh()
        #expect(await downloads.list.downloads.count == 3)

        await downloads.remove(bookFileID: 31)
        #expect(await downloads.downloaded(epub) == nil)
        #expect(await downloads.list.totalBytes == 10)

        await downloads.removeAllFinished()
        #expect(await downloads.list.downloads.map(\.bookFileID) == [4])
        #expect(await downloads.downloaded(audiobook) == nil)
    }
}
