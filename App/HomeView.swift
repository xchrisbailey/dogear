import DogearCore
import SwiftUI

struct HomeView: View {
    let session: Session

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let warning = session.versionWarning {
                    Label(warning.message, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.yellow.opacity(0.2))
                }
                ContentUnavailableView(
                    "Your library",
                    systemImage: "books.vertical",
                    description: Text("Signed in as \(session.username) on \(session.server.host() ?? "your Server").")
                )
            }
            .navigationTitle("Library")
            .toolbar { SignOutButton() }
        }
    }
}
