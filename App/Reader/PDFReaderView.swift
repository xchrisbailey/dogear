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
                    ReaderBar(title: title) { dismiss() } actions: {
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
            switch phase {
            case .active: Task { await model.catchUp() }
            // The page just turned may still be waiting for the push delay.
            case .background: BackgroundTime.finish("Send the last page read") { await model.sendNow() }
            default: break
            }
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
                .tint(.white)
                .foregroundStyle(.white)
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

    @Environment(\.palette) private var palette

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
        .font(.footnote)
        .foregroundStyle(palette.textSecondary)
        .monospacedDigit()
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(palette.canvas.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { palette.outline.frame(height: 1) }
        .accessibilityElement(children: .combine)
    }
}
