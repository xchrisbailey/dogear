import DogearCore
@preconcurrency import ReadiumNavigator
@preconcurrency import ReadiumShared
import SwiftUI

/// Full-screen reader for one EPUB Book file.
struct EPUBReaderView: View {
    let title: String
    @State var model: EPUBReaderModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var isShowingContents = false
    @State private var isShowingSettings = false

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            Desk()
            content
            if showsBar {
                VStack(spacing: 0) {
                    LeatherBar(title: title) { dismiss() } actions: {
                        Button("Contents", systemImage: "list.bullet") { isShowingContents = true }
                            .disabled(model.tableOfContents.isEmpty)
                        Button("Reading Settings", systemImage: "textformat.size") { isShowingSettings = true }
                    }
                    if let problem = model.problem {
                        PaperSlip(text: problem) { model.problem = nil }
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: showsBar)
        .statusBarHidden(!showsBar)
        .sheet(isPresented: $isShowingContents) {
            ContentsView(tableOfContents: model.tableOfContents) { await model.go(to: $0) }
        }
        .sheet(isPresented: $isShowingSettings) {
            ReadingSettingsView(preferences: $model.preferences)
                .presentationDetents([.medium, .large])
        }
        .task { await model.open() }
        .onDisappear { Task { await model.close() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.catchUp() } }
        }
    }

    /// The bar lies over the page, so showing it never lays the page out again. It stays while
    /// there is no page to tap.
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
            let paper = ReaderPaper(model.preferences.theme ?? .light)
            GeometryReader { geometry in
                let style = model.turnStyle(in: geometry.size, isWide: horizontalSizeClass == .regular, reduceMotion: reduceMotion)
                OpenBook(paper: paper, showsPageEdges: style != .none) {
                    VStack(spacing: 0) {
                        BookPages(navigator: navigator, style: style) { model.toggleControls() }
                            // Rotation and spreads resize the page, and Readium reports where it lands.
                            .onGeometryChange(for: CGSize.self, of: \.size) { _ in model.relocated() }
                        Folio(model: model, ink: SwiftUI.Color(hex: paper.ink))
                    }
                }
            }
            .environment(\.layoutDirection, model.isRightToLeft ? .rightToLeft : .leftToRight)
        }
    }
}

/// The line at the foot of the page, like a printed folio: the Chapter, and how far through it
/// and the whole Book file the reader is.
private struct Folio: View {
    let model: EPUBReaderModel
    let ink: SwiftUI.Color

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
        .font(.system(.caption, design: .serif).italic())
        .foregroundStyle(ink.opacity(0.75))
        .monospacedDigit()
        .padding(.leading, 28)
        .padding(.trailing, 16)
        .padding(.vertical, 8)
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
                    Text("Light").tag(ReadiumNavigator.Theme.light)
                    Text("Sepia").tag(ReadiumNavigator.Theme.sepia)
                    Text("Dark").tag(ReadiumNavigator.Theme.dark)
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
