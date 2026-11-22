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
    @State private var isShowingDownloads = false
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $preferredColumn) {
            LibrarySidebar(navigation: navigation, scope: $scope)
        } detail: {
            NavigationStack {
                Group {
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
                // Inside the NavigationStack so the notices sit below the navigation bar instead
                // of under its buttons, and stay out of the way of the list's scrolling.
                .safeAreaInset(edge: .top, spacing: 0) {
                    SessionNotices(session: session, serverStatus: serverStatus)
                }
                .toolbar {
                    OutboxIndicator()
                    // Downloads made before the account lost `canDownload` still need managing.
                    if model.downloadList.canDownload || !model.downloadList.downloads.isEmpty {
                        Button("Downloads", systemImage: "arrow.down.circle") { isShowingDownloads = true }
                    }
                    AccountMenu(session: session)
                }
                .sheet(isPresented: $isShowingDownloads) { DownloadsView() }
            }
        }
        // Under both columns, so the audiobook stays in reach wherever the library is.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let nowPlaying = model.nowPlaying {
                NowPlayingBar(player: nowPlaying.player) { model.isShowingPlayer = true }
            }
        }
        // By item, so the player stays drawn as it slides away after an Eject.
        .fullScreenCover(item: Binding {
            model.isShowingPlayer ? model.nowPlaying : nil
        } set: {
            if $0 == nil { model.isShowingPlayer = false }
        }) { nowPlaying in
            AudiobookPlayerView(model: nowPlaying.player, cover: nowPlaying.cover, library: library)
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
