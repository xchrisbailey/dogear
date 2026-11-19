import DogearCore
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

    init(account: Account) {
        self.account = account
        library = (try? LibraryStore.onDevice()).map { Library(account: account, store: $0) }
    }

    /// Follows the Session for the app's lifetime, so a refused refresh anywhere shows up here.
    func observeSession() async {
        for await session in await account.sessionUpdates() {
            self.session = session
            hasRestored = true
        }
    }

    func signIn(address: String, username: String, password: String) async throws(SignInError) {
        session = try await account.signIn(address: address, username: username, password: password)
    }

    /// Positions not yet accepted by the Server. Returns 0 until the Outbox exists.
    func outboxCount() async -> Int {
        0
    }

    func signOut() async {
        await account.signOut()
        await library?.forget()
        session = nil
    }
}

struct RootView: View {
    let model: AppModel

    var body: some View {
        Group {
            if let session = model.session {
                HomeView(session: session, library: model.library)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        if session.needsSignIn { NeedsSignInBanner(session: session) }
                    }
            } else if model.hasRestored {
                SignInView(model: model)
            } else {
                ProgressView()
            }
        }
        .environment(model)
        .task { await model.observeSession() }
    }
}
