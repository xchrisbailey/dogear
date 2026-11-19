import DogearCore
import Network
import SwiftUI

@main
struct DogearApp: App {
    @State private var model = AppModel(account: Account(tokenStore: KeychainTokenStore()))

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
    /// Positions waiting for the Server.
    private(set) var outboxCount = 0
    private(set) var serverStatus = ServerStatus()

    init(account: Account) {
        self.account = account
        library = (try? LibraryStore.onDevice()).map { Library(account: account, store: $0) }
        positions = (try? PositionStore.onDevice()).map { Positions(store: $0) }
        sharedPositions = SharedPositions(account: account)
    }

    /// A reader for the Book's EPUB, streamed from the Server. nil when signed out.
    func epubReader(for book: Book, file: BookFile) async -> EPUBReaderModel? {
        guard let epub = await ServerEPUB(account: account, bookID: book.id) else { return nil }
        return EPUBReaderModel(
            epub: epub, bookFileID: file.id, positions: positions, sharedPositions: sharedPositions
        )
    }

    /// A reader for the Book's PDF, fetched from the Server. nil when signed out.
    func pdfReader(for book: Book, file: BookFile) async -> PDFReaderModel? {
        guard let pdf = await ServerPDF(account: account, bookID: book.id) else { return nil }
        return PDFReaderModel(
            pdf: pdf, bookFileID: file.id, positions: positions, sharedPositions: sharedPositions
        )
    }

    /// A player for the Book's audiobook, streamed from the Server. nil when signed out.
    func audiobookPlayer(for book: Book) async -> AudiobookPlayerModel? {
        guard let audiobook = await ServerAudiobook(account: account, bookID: book.id) else { return nil }
        let cover = book.audiobookCover ?? book.cover
        return AudiobookPlayerModel(
            audiobook: audiobook, title: book.title, author: book.authors.first,
            positions: positions, sharedPositions: sharedPositions
        ) { [library] in
            guard let cover else { return nil }
            return await library?.image(for: cover)
        }
    }

    /// Follows the Session for the app's lifetime, so a refused refresh anywhere shows up here.
    /// Each usable Session flushes the Outbox, which covers launch and signing in again.
    func observeSession() async {
        for await session in await account.sessionUpdates() {
            self.session = session
            hasRestored = true
            if let session, !session.needsSignIn { await flushOutbox() }
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
    func flushOutbox() async {
        try? await positions?.flushOutbox(to: sharedPositions)
    }

    func signIn(address: String, username: String, password: String) async throws(SignInError) {
        session = try await account.signIn(address: address, username: username, password: password)
    }

    /// Clears the Outbox along with everything else; `SignOutButton` warns first if it isn't empty.
    func signOut() async {
        await account.signOut()
        await library?.forget()
        await positions?.forget()
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
                    .safeAreaInset(edge: .top, spacing: 0) {
                        VStack(spacing: 0) {
                            if session.needsSignIn { NeedsSignInBanner(session: session) }
                            ServerStatusBanner(status: model.serverStatus)
                        }
                    }
            } else if model.hasRestored {
                SignInView(model: model)
            } else {
                ProgressView()
            }
        }
        .environment(model)
        .task { await model.observeSession() }
        .task { await model.observeOutbox() }
        .task { await model.observeServerStatus() }
        .task { await model.retryWhileOffline() }
        // Coming back to the app is the likeliest moment the Server is reachable again.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await model.checkServerIfOffline()
                    await model.flushOutbox()
                }
            }
        }
    }
}
