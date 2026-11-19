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

/// Offline mode, or a Server that has changed under Dogear. Either way the local library and
/// the Outbox carry on.
struct ServerStatusBanner: View {
    let status: ServerStatus

    var body: some View {
        if let message = status.message {
            Label(message, systemImage: status.hasChanged ? "exclamationmark.arrow.triangle.2.circlepath" : "wifi.slash")
                .font(.footnote)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(status.hasChanged ? Color.red.opacity(0.15) : Color.secondary.opacity(0.15))
        }
    }
}

struct SignOutButton: View {
    @Environment(AppModel.self) private var model
    @State private var isConfirming = false

    /// Downloads go too: another account or Server numbers its Books differently.
    private var warning: String {
        switch (model.outboxCount > 0, !model.downloadList.downloads.isEmpty) {
        case (true, true): "Some of your reading progress hasn't reached your Server yet. Signing out discards it and removes your Downloads from this device."
        case (true, false): "Some of your reading progress hasn't reached your Server yet. Signing out discards it."
        default: "Signing out removes your Downloads from this device."
        }
    }

    var body: some View {
        Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right") {
            if model.outboxCount > 0 || !model.downloadList.downloads.isEmpty {
                isConfirming = true
            } else {
                Task { await model.signOut() }
            }
        }
        .confirmationDialog(
            warning,
            isPresented: $isConfirming,
            titleVisibility: .visible
        ) {
            Button("Sign Out Anyway", role: .destructive) {
                Task { await model.signOut() }
            }
        }
    }
}

/// A quiet note that some reading hasn't reached the Server yet.
struct OutboxIndicator: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.outboxCount > 0 {
            Image(systemName: "icloud.and.arrow.up")
                .foregroundStyle(.secondary)
                .accessibilityLabel(model.outboxCount == 1
                    ? "1 Position waiting to sync"
                    : "\(model.outboxCount) Positions waiting to sync")
                .help("Reading progress waiting to sync")
        }
    }
}
