import DogearCore
@preconcurrency import ReadiumNavigator
import SwiftUI

/// Full-screen reader for one PDF Book file.
struct PDFReaderView: View {
    let title: String
    @State var model: PDFReaderModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var isShowingContents = false

    var body: some View {
        ZStack {
            Desk()
            VStack(spacing: 0) {
                if showsBar {
                    LeatherBar(title: title) { dismiss() } actions: {
                        Button("Contents", systemImage: "list.bullet") { isShowingContents = true }
                            .disabled(model.tableOfContents.isEmpty)
                    }
                }
                content
            }
        }
        .statusBarHidden(!showsBar)
        .sheet(isPresented: $isShowingContents) {
            ContentsView(tableOfContents: model.tableOfContents) { await model.go(to: $0) }
        }
        .task { await model.open() }
        .onDisappear { Task { await model.close() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.catchUp() } }
        }
    }

    /// The bar stays while there is no page to tap.
    private var showsBar: Bool {
        if case .reading = model.state { model.isShowingControls } else { true }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .opening:
            ProgressView("Opening…")
                .tint(Theme.foil)
                .foregroundStyle(Theme.foil)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(message):
            ContentUnavailableView("Can't open this Book", systemImage: "exclamationmark.triangle", description: Text(message))
                .environment(\.colorScheme, .dark)
        case let .reading(navigator):
            PDFNavigatorView(navigator: navigator)
                .ignoresSafeArea(edges: .bottom)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    PagePosition(page: model.page, pageCount: model.pageCount)
                }
        }
    }
}

private struct PDFNavigatorView: UIViewControllerRepresentable {
    let navigator: PDFNavigatorViewController
    func makeUIViewController(context: Context) -> PDFNavigatorViewController { navigator }
    func updateUIViewController(_ navigator: PDFNavigatorViewController, context: Context) {}
}

/// The page and how far through the whole Book file it is.
private struct PagePosition: View {
    let page: Int?
    let pageCount: Int?

    var body: some View {
        HStack {
            if let page {
                Text(pageCount.map { "Page \(page) of \($0)" } ?? "Page \(page)")
            }
            Spacer()
            if let page, let pageCount, pageCount > 0 {
                Text((Double(page) / Double(pageCount)).formatted(.percent.precision(.fractionLength(0))))
            }
        }
        .font(.system(.caption, design: .serif).italic())
        .foregroundStyle(Theme.gilt)
        .monospacedDigit()
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Theme.desk[1])
        .accessibilityElement(children: .combine)
    }
}
