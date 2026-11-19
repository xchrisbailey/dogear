import DogearCore
@preconcurrency import ReadiumNavigator
@preconcurrency import ReadiumShared
import SwiftUI

/// Full-screen reader for one EPUB Book file.
struct EPUBReaderView: View {
    let title: String
    @State var model: EPUBReaderModel

    @Environment(\.dismiss) private var dismiss
    @State private var isShowingContents = false
    @State private var isShowingSettings = false

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
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button("Contents", systemImage: "list.bullet") { isShowingContents = true }
                            .disabled(model.tableOfContents.isEmpty)
                        Button("Reading Settings", systemImage: "textformat.size") { isShowingSettings = true }
                    }
                }
                .sheet(isPresented: $isShowingContents) {
                    ContentsView(tableOfContents: model.tableOfContents) { await model.go(to: $0) }
                }
                .sheet(isPresented: $isShowingSettings) {
                    ReadingSettingsView(preferences: $model.preferences)
                        .presentationDetents([.medium, .large])
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
            NavigatorView(navigator: navigator)
                .ignoresSafeArea(edges: .bottom)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    ReadingProgress(model: model)
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    if let problem = model.problem {
                        Label(problem, systemImage: "wifi.exclamationmark")
                            .font(.footnote)
                            .padding(8)
                            .frame(maxWidth: .infinity)
                            .background(.orange.opacity(0.2))
                            .onTapGesture { model.problem = nil }
                    }
                }
        }
    }
}

private struct NavigatorView: UIViewControllerRepresentable {
    let navigator: EPUBNavigatorViewController
    func makeUIViewController(context: Context) -> EPUBNavigatorViewController { navigator }
    func updateUIViewController(_ navigator: EPUBNavigatorViewController, context: Context) {}
}

/// Progress through the Chapter and the whole Book file.
private struct ReadingProgress: View {
    let model: EPUBReaderModel

    var body: some View {
        let locations = model.location?.locations
        HStack {
            Text(model.chapterTitle ?? " ")
                .lineLimit(1)
            Spacer()
            if let chapter = locations?.progression {
                Text("\(chapter.formatted(.percent.precision(.fractionLength(0)))) of chapter")
            }
            if let book = locations?.totalProgression {
                Text("· \(book.formatted(.percent.precision(.fractionLength(0)))) of book")
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

/// A Book file's table of contents; choosing an entry jumps there.
struct ContentsView: View {
    let tableOfContents: [ReadiumShared.Link]
    let go: (ReadiumShared.Link) async -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                OutlineGroup(tableOfContents.map(ContentsEntry.init), children: \.children) { entry in
                    Button(entry.link.title ?? entry.link.href) {
                        Task { await go(entry.link) }
                        dismiss()
                    }
                    .foregroundStyle(.primary)
                }
            }
            .navigationTitle("Contents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// A table of contents entry with stable identity for `OutlineGroup`.
private struct ContentsEntry: Identifiable {
    let id = UUID()
    let link: ReadiumShared.Link
    /// nil for leaves, so they don't show a disclosure arrow.
    let children: [ContentsEntry]?

    init(_ link: ReadiumShared.Link) {
        self.link = link
        children = link.children.isEmpty ? nil : link.children.map(ContentsEntry.init)
    }
}

/// Font, theme, margins and paged or scroll mode.
private struct ReadingSettingsView: View {
    @Binding var preferences: EPUBPreferences

    private static let fonts: [(name: String, family: FontFamily?)] = [
        ("Publisher's font", nil),
        ("Iowan Old Style", .iowanOldStyle),
        ("Georgia", .georgia),
        ("Palatino", .palatino),
        ("Athelas", .athelas),
        ("Helvetica Neue", .helveticaNeue),
        ("Seravek", .seravek),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Picker("Font", selection: $preferences.fontFamily) {
                    ForEach(Self.fonts, id: \.name) { font in
                        Text(font.name).tag(font.family)
                    }
                }
                LabeledContent("Text size") {
                    Stepper(
                        (preferences.fontSize ?? 1).formatted(.percent.precision(.fractionLength(0))),
                        value: Binding { preferences.fontSize ?? 1 } set: { preferences.fontSize = $0 },
                        in: 0.6 ... 2.5,
                        step: 0.1
                    )
                }
                Picker("Theme", selection: Binding { preferences.theme ?? .light } set: { preferences.theme = $0 }) {
                    Text("Light").tag(Theme.light)
                    Text("Sepia").tag(Theme.sepia)
                    Text("Dark").tag(Theme.dark)
                }
                .pickerStyle(.segmented)
                LabeledContent("Margins") {
                    Slider(
                        value: Binding { preferences.pageMargins ?? 1 } set: { preferences.pageMargins = $0 },
                        in: 0.5 ... 2.5,
                        step: 0.25
                    )
                    .frame(maxWidth: 200)
                }
                Picker("Layout", selection: Binding { preferences.scroll ?? false } set: { preferences.scroll = $0 }) {
                    Text("Pages").tag(false)
                    Text("Scroll").tag(true)
                }
                .pickerStyle(.segmented)
                Picker("Pages side by side", selection: Binding { PageSpread(preferences) } set: { $0.apply(to: &preferences) }) {
                    ForEach(PageSpread.allCases, id: \.self) { spread in
                        Text(spread.name).tag(spread)
                    }
                }
                .disabled(preferences.scroll == true)
            }
            .navigationTitle("Reading Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
