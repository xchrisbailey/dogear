import DogearCore
import SwiftUI

/// The library in a split view: libraries and shelves in a sidebar, Books beside them.
///
/// One hierarchy for every width, so resizing an iPad split view keeps the search, the scroll
/// position and an open reader. Compact widths collapse to the Books with a back button to the sidebar.
struct HomeView: View {
    let session: Session
    let library: Library?
    let serverStatus: ServerStatus

    @State private var scope: BookScope? = .everything
    @State private var navigation = Navigation()
    @State private var preferredColumn = NavigationSplitViewColumn.detail

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $preferredColumn) {
            LibrarySidebar(navigation: navigation, scope: $scope)
        } detail: {
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
                        LibraryView(
                            library: library,
                            // Reaching the Server again reloads the list.
                            canSync: !session.needsSignIn && serverStatus.isReachable,
                            scope: Binding { scope ?? .everything } set: { scope = $0 },
                            navigation: $navigation
                        )
                    } else {
                        ContentUnavailableView(
                            "Library unavailable",
                            systemImage: "exclamationmark.triangle",
                            description: Text("Dogear couldn't open its storage on this device.")
                        )
                    }
                }
                .toolbar {
                    OutboxIndicator()
                    SignOutButton()
                }
            }
        }
    }
}

/// Picks everything, one Grimmory library, or one shelf.
private struct LibrarySidebar: View {
    let navigation: Navigation
    @Binding var scope: BookScope?

    var body: some View {
        List(selection: $scope) {
            Label("All Books", systemImage: "books.vertical")
                .tag(BookScope.everything)
            if !navigation.libraries.isEmpty {
                Section("Libraries") {
                    ForEach(navigation.libraries) { library in
                        Label(library.name, systemImage: "building.columns")
                            .tag(BookScope.library(library.id))
                    }
                }
            }
            if !navigation.shelves.isEmpty {
                Section("Shelves") {
                    ForEach(navigation.shelves) { shelf in
                        Label(shelf.name, systemImage: "bookmark")
                            .tag(BookScope.shelf(shelf.id))
                    }
                }
            }
        }
        .navigationTitle("Library")
    }
}
