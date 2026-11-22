import DogearCore
import Network
import SwiftUI
import TipKit

@main
struct DogearApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var model = AppModel(account: Account(tokenStore: KeychainTokenStore(), passwordStore: KeychainPasswordStore()))

    init() {
        try? Tips.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
    }
}

@Observable
final class AppModel {
    private let account: Account
    private(set) var session: Session?
    private(set) var hasRestored = false
    /// nil only if the on-device store can't be opened; the library then can't be shown.
    let library: Library?
    /// nil only if the on-device store can't be opened; Books then open at the start.
    let positions: Positions?
    private let sharedPositions: SharedPositions
    /// nil only if the Downloads folder can't be created; download options are then hidden.
    let downloads: Downloads?
    private(set) var downloadList = DownloadList()
    /// Positions waiting for the Server.
    private(set) var outboxCount = 0
    private(set) var serverStatus = ServerStatus()
    /// Continue Reading and Continue Listening, kept current as Positions change here or on the Server.
    private(set) var continueRows = ContinueRows()
    /// The latest Position in every Book file read on this device, for showing how far in each Book is.
    private(set) var recordedPositions: [Position] = []
    /// The audiobook in the player. It plays on while the player is closed, until it's ejected.
    private(set) var nowPlaying: NowPlaying?
    /// Whether the player is open over the library.
    var isShowingPlayer = false

    struct NowPlaying: Identifiable {
        let player: AudiobookPlayerModel
        let cover: Cover?

        var id: ObjectIdentifier { ObjectIdentifier(player) }
    }

    init(account: Account) {
        self.account = account
        library = (try? LibraryStore.onDevice()).map { Library(account: account, store: $0) }
        positions = (try? PositionStore.onDevice()).map { Positions(store: $0) }
        sharedPositions = SharedPositions(account: account)
        let transport = BackgroundTransport()
        downloads = try? Downloads.onDevice(account: account, transport: transport)
        if let downloads { transport.attach(downloads) }
        // Earlier versions kept every opened PDF here for offline reading, which is a Download
        // in all but name and ignored `canDownload`.
        if let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            try? FileManager.default.removeItem(at: caches.appending(path: "PDFs"))
        }
    }

    /// Follows the Downloads for the app's lifetime, starting again whatever iOS dropped while
    /// the app wasn't running.
    func observeDownloads() async {
        guard let downloads else { return }
        await downloads.resumeTransfers()
        for await list in await downloads.updates() {
            downloadList = list
        }
    }

    /// Shows a failure to start; once started, progress and failures show in `downloadList`.
    func download(_ file: BookFile, of book: Book) async throws(DownloadError) {
        guard let downloads else { throw .couldNotSave }
        try await downloads.download(file, of: book)
    }

    func removeDownload(of file: BookFile) async {
        await downloads?.remove(bookFileID: file.id)
    }

    /// A reader for the Book's EPUB, from its Download or streamed from the Server, or for its
    /// MOBI, AZW3 or FB2 converted to an EPUB. nil when signed out.
    func epubReader(for book: Book, file: BookFile) async -> EPUBReaderModel? {
        guard let epub = await ServerEPUB(account: account, bookID: book.id) else { return nil }
        let source: EPUBReaderModel.Source
        switch await downloads?.downloaded(file) {
        case let .epub(url)?:
            source = .download(url)
        case let .convertible(url)?:
            source = .converted(format: file.format) { try Data(contentsOf: url) }
        default:
            if file.format.isConvertedToEPUB {
                guard let served = await ServerConvertible(account: account, bookID: book.id, format: file.format) else { return nil }
                source = .converted(format: file.format) { try await served.contents() }
            } else {
                source = .server
            }
        }
        return EPUBReaderModel(
            epub: epub, source: source, bookFileID: file.id, positions: positions, sharedPositions: sharedPositions
        )
    }

    /// A reader for the Book's PDF, from its Download or fetched from the Server. nil when signed out.
    func pdfReader(for book: Book, file: BookFile) async -> PDFReaderModel? {
        guard let pdf = await ServerPDF(account: account, bookID: book.id) else { return nil }
        var downloaded: URL?
        if case let .pdf(url)? = await downloads?.downloaded(file) { downloaded = url }
        return PDFReaderModel(
            pdf: pdf, downloaded: downloaded, bookFileID: file.id, positions: positions, sharedPositions: sharedPositions
        )
    }

    /// A player for the Book's audiobook, from its Download or streamed from the Server. nil when signed out.
    func audiobookPlayer(for book: Book) async -> AudiobookPlayerModel? {
        let file = book.files.first { $0.format == .audiobook }
        let audiobook: any AudiobookSource
        if let file, case let .audiobook(downloaded)? = await downloads?.downloaded(file) {
            audiobook = downloaded
        } else if let streamed = await ServerAudiobook(account: account, bookID: book.id) {
            audiobook = streamed
        } else {
            return nil
        }
        let cover = book.audiobookCover ?? book.cover
        return AudiobookPlayerModel(
            audiobook: audiobook, title: book.title, author: book.authors.first,
            positions: positions, sharedPositions: sharedPositions
        ) { [library] in
            guard let cover else { return nil }
            return await library?.image(for: cover)
        }
    }

    /// Opens the player on the Book's audiobook. The one already loaded just opens again; another
    /// one is ejected first.
    func play(_ book: Book) async {
        if let nowPlaying, nowPlaying.player.bookID == book.id {
            isShowingPlayer = true
            return
        }
        guard let player = await audiobookPlayer(for: book) else { return }
        await eject()
        nowPlaying = NowPlaying(player: player, cover: book.audiobookCover ?? book.cover)
        isShowingPlayer = true
        // Not tied to the player's screen, which can close while the audiobook is still opening.
        Task { await player.open() }
    }

    /// Stops the audiobook, saves its Position and closes the player.
    func eject() async {
        guard let nowPlaying else { return }
        self.nowPlaying = nil
        isShowingPlayer = false
        await nowPlaying.player.close()
    }

    /// Follows the Session for the app's lifetime, so a refused refresh anywhere shows up here.
    /// Each usable Session flushes the Outbox, which covers launch and signing in again.
    func observeSession() async {
        for await session in await account.sessionUpdates() {
            self.session = session
            hasRestored = true
            if let session, !session.needsSignIn {
                await flushOutbox()
                await downloads?.checkPermission()
            }
        }
    }

    /// Follows whether the Server is reachable and understood. Coming back online flushes the Outbox.
    func observeServerStatus() async {
        for await status in await account.serverStatusUpdates() {
            let cameBack = !serverStatus.isReachable && status.isReachable
            serverStatus = status
            if cameBack { await flushOutbox() }
        }
    }

    /// While offline, asks the Server again whenever the network changes, such as rejoining the
    /// tailnet, and every so often in case nothing on the device noticed.
    func retryWhileOffline() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await _ in Self.networkChanges() { await self.checkServerIfOffline() }
            }
            group.addTask {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(30))
                    await self.checkServerIfOffline()
                }
            }
        }
    }

    func checkServerIfOffline() async {
        guard !serverStatus.isReachable else { return }
        await account.checkServer()
    }

    nonisolated private static func networkChanges() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                if path.status == .satisfied { continuation.yield() }
            }
            continuation.onTermination = { _ in monitor.cancel() }
            monitor.start(queue: DispatchQueue(label: "dogear.network"))
        }
    }

    func observeOutbox() async {
        guard let positions else { return }
        for await count in await positions.outboxCountUpdates() {
            outboxCount = count
        }
    }

    /// Failures leave the Outbox as it is for the next try; the indicator shows it's waiting.
    /// Afterwards the Server's continue rows include what was just sent.
    func flushOutbox() async {
        try? await positions?.flushOutbox(to: sharedPositions)
        try? await library?.refreshContinueRows()
        await showContinueRows()
    }

    /// Recomputes the rows from the cache and this device's Positions, which works offline.
    func showContinueRows() async {
        recordedPositions = await positions?.all() ?? []
        guard let library else { return }
        continueRows = await library.continueRows(including: recordedPositions)
    }

    func observePositions() async {
        guard let positions else { return }
        let changes = await positions.changes()
        await showContinueRows()
        for await _ in changes {
            await showContinueRows()
        }
    }

    func signIn(address: String, username: String, password: String) async throws(SignInError) {
        session = try await account.signIn(address: address, username: username, password: password)
    }

    /// Clears the Outbox along with everything else; `AccountMenu` warns first if it isn't empty.
    func signOut() async {
        await eject()
        await account.signOut()
        await library?.forget()
        await positions?.forget()
        await downloads?.removeAll()
        continueRows = ContinueRows()
        recordedPositions = []
        session = nil
    }
}

struct RootView: View {
    let model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if let session = model.session {
                HomeView(session: session, library: model.library, serverStatus: model.serverStatus)
            } else if model.hasRestored {
                SignInView(model: model)
            } else {
                ProgressView()
            }
        }
        .environment(model)
        .task { await model.observeSession() }
        .task { await model.observeOutbox() }
        .task { await model.observeDownloads() }
        .task { await model.observePositions() }
        .task { await model.observeServerStatus() }
        .task { await model.retryWhileOffline() }
        // Coming back to the app is the likeliest moment the Server is reachable again.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await model.checkServerIfOffline()
                    await model.flushOutbox()
                }
                // Here and not in the player, which may be closed while its audiobook is loaded.
                Task { await model.nowPlaying?.player.catchUp() }
            }
        }
    }
}
