import DogearCore
@preconcurrency import ReadiumNavigator
import SwiftUI

/// Full-screen reader for one PDF Book file.
struct PDFReaderView: View {
    let title: String
    @State var model: PDFReaderModel

    @Environment(\.dismiss) private var dismiss
    @State private var isShowingContents = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(model.isShowingControls ? .visible : .hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", systemImage: "xmark") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("Contents", systemImage: "list.bullet") { isShowingContents = true }
                            .disabled(model.tableOfContents.isEmpty)
                    }
                }
                .sheet(isPresented: $isShowingContents) {
                    ContentsView(tableOfContents: model.tableOfContents) { await model.go(to: $0) }
                }
                .task { await model.open() }
                .onDisappear { Task { await model.close() } }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .opening:
            ProgressView("Opening…")
        case let .failed(message):
            ContentUnavailableView("Can't open this Book", systemImage: "exclamationmark.triangle", description: Text(message))
        case let .reading(navigator):
            PDFNavigatorView(navigator: navigator)
                .ignoresSafeArea(edges: .bottom)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    PageProgress(page: model.page, pageCount: model.pageCount)
                }
        }
    }
}

private struct PDFNavigatorView: UIViewControllerRepresentable {
    let navigator: PDFNavigatorViewController
    func makeUIViewController(context: Context) -> PDFNavigatorViewController { navigator }
    func updateUIViewController(_ navigator: PDFNavigatorViewController, context: Context) {}
}

/// The page and progress through the whole Book file.
private struct PageProgress: View {
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
        .font(.caption)
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .padding(.horizontal)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}
