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

    init(account: Account) {
        self.account = account
    }

    func restore() async {
        session = await account.session
        hasRestored = true
    }

    func signIn(address: String, username: String, password: String) async throws(SignInError) {
        session = try await account.signIn(address: address, username: username, password: password)
    }
}

struct RootView: View {
    let model: AppModel

    var body: some View {
        Group {
            if let session = model.session {
                HomeView(session: session)
            } else if model.hasRestored {
                SignInView(model: model)
            } else {
                ProgressView()
            }
        }
        .task { await model.restore() }
    }
}
