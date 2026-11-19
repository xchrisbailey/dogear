import DogearCore
import SwiftUI

/// Shown while the Server refuses the refresh token. Local data stays usable offline.
struct NeedsSignInBanner: View {
    let session: Session

    @Environment(AppModel.self) private var model
    @State private var isSigningIn = false

    var body: some View {
        HStack {
            Label("Your sign-in has expired. Sign in again to sync.", systemImage: "person.crop.circle.badge.exclamationmark")
                .font(.footnote)
            Spacer()
            Button("Sign In") { isSigningIn = true }
                .font(.footnote.bold())
        }
        .padding()
        .background(.orange.opacity(0.2))
        .sheet(isPresented: $isSigningIn) {
            SignInView(model: model, address: session.server.absoluteString, username: session.username)
        }
    }
}

struct SignOutButton: View {
    @Environment(AppModel.self) private var model
    @State private var isConfirming = false

    var body: some View {
        Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right") {
            Task {
                if await model.outboxCount() > 0 {
                    isConfirming = true
                } else {
                    await model.signOut()
                }
            }
        }
        .confirmationDialog(
            "Some of your reading progress hasn't reached your Server yet. Signing out discards it.",
            isPresented: $isConfirming,
            titleVisibility: .visible
        ) {
            Button("Sign Out Anyway", role: .destructive) {
                Task { await model.signOut() }
            }
        }
    }
}
