import DogearCore
import SwiftUI

/// The notices above the library: an expired sign-in, offline mode or a changed Server, and an
/// untested Grimmory version. Local data stays usable offline whichever is showing.
struct SessionNotices: View {
    let session: Session
    let serverStatus: ServerStatus

    var body: some View {
        VStack(spacing: 8) {
            if session.needsSignIn { NeedsSignInBanner(session: session) }
            if let message = serverStatus.message {
                NoticeBanner(
                    title: serverStatus.hasChanged ? "Server has changed" : "Offline",
                    message: message,
                    systemImage: serverStatus.hasChanged ? "exclamationmark.arrow.triangle.2.circlepath" : "wifi.slash",
                    tint: serverStatus.hasChanged ? .red : .secondary
                )
            }
            if let warning = session.versionWarning {
                NoticeBanner(
                    title: "Untested Server version",
                    message: warning.message,
                    systemImage: "exclamationmark.triangle",
                    tint: .yellow
                )
            }
        }
        .padding(.horizontal)
        .padding(.vertical, hasNotices ? 8 : 0)
    }

    private var hasNotices: Bool {
        session.needsSignIn || serverStatus.message != nil || session.versionWarning != nil
    }
}

/// Shown while the Server refuses the refresh token and no saved password could renew it.
struct NeedsSignInBanner: View {
    let session: Session

    @Environment(AppModel.self) private var model
    @State private var isSigningIn = false

    var body: some View {
        NoticeBanner(
            title: "Sign-in expired",
            message: "Sign in again to sync your reading progress. Everything on this device still works.",
            systemImage: "person.crop.circle.badge.exclamationmark",
            tint: .orange
        ) {
            Button("Sign In") { isSigningIn = true }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.small)
        }
        .sheet(isPresented: $isSigningIn) {
            SignInView(model: model, address: session.server.absoluteString, username: session.username)
        }
    }
}

/// A notice on a paper tag that wraps its text rather than squeezing it, with an optional action.
/// `tint` colors the tag's edge: orange to act, red for trouble, grey for information.
struct NoticeBanner<Action: View>: View {
    let title: String
    let message: String
    let systemImage: String
    let tint: Color
    @ViewBuilder var action: Action

    @Environment(\.palette) private var palette

    var body: some View {
        PaperTag(edge: tint) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(palette.inkSecondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.label(.subheadline))
                        .foregroundStyle(palette.ink)
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                action
            }
        }
        .accessibilityElement(children: .contain)
    }
}

extension NoticeBanner where Action == EmptyView {
    init(title: String, message: String, systemImage: String, tint: Color) {
        self.init(title: title, message: message, systemImage: systemImage, tint: tint) { EmptyView() }
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
