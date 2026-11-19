import DogearCore
import SwiftUI

struct HomeView: View {
    let session: Session
    let library: Library?

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
                if let library {
                    LibraryView(library: library, canSync: !session.needsSignIn)
                } else {
                    ContentUnavailableView(
                        "Library unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text("Dogear couldn't open its storage on this device.")
                    )
                }
            }
            .navigationTitle("Library")
            .toolbar { SignOutButton() }
        }
    }
}
