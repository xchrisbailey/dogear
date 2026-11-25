import DogearCore
@preconcurrency import ReadiumNavigator
import SwiftUI

/// Everything the reader can set for the whole app: the app theme, their account, the reader's
/// defaults, the player's keys, Downloads and versions. Paper cards on the theme's canvas.
struct SettingsView: View {
    let session: Session

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// The same values the reader's own sheet edits, so the two never disagree.
    @State private var reading = ReadingPreferences.load()
    @State private var listening = ListeningPreferences.load()
    /// The root reads the same key, so a new theme shows at once, even mid-listen.
    @AppStorage(AppearancePreferences.themeKey) private var storedTheme: String?
    @Environment(\.palette) private var palette
    @State private var isShowingDownloads = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Settings")
                        .serifTitle(34, relativeTo: .largeTitle)
                        .foregroundStyle(palette.text)
                        .padding(.horizontal, 4)
                        .padding(.top, 4)
                        .accessibilityAddTraits(.isHeader)
                    SettingsSection("Appearance") {
                        ThemeTiles(selection: Binding { AppTheme(stored: storedTheme) } set: { storedTheme = $0.rawValue })
                    }
                    SettingsSection("Account") { account }
                    SettingsSection("Reading") { readingRows }
                    SettingsSection("Listening") { listeningRows }
                    if model.downloadList.canDownload || !model.downloadList.downloads.isEmpty {
                        SettingsSection("Downloads") { downloads }
                    }
                    SettingsSection("About") { about }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
            .background { CanvasBackground() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(palette.canvas, for: .navigationBar)
            .toolbarColorScheme(palette.scheme, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .tint(palette.canvasAction)
                }
            }
            .sheet(isPresented: $isShowingDownloads) { DownloadsView() }
        }
        .onChange(of: reading) { _, reading in ReadingPreferences.save(reading) }
        .onChange(of: listening) { _, listening in
            ListeningPreferences.save(listening)
            model.nowPlaying?.player.apply(listening)
        }
    }

    // MARK: Account

    @ViewBuilder private var account: some View {
        SettingsRow {
            HStack(spacing: 12) {
                Text(session.username.prefix(1).uppercased())
                    .font(.headline)
                    .foregroundStyle(palette.onAccent)
                    .frame(width: 40, height: 40)
                    .background(palette.accent, in: .circle)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.username)
                    Text(session.server.host() ?? session.server.absoluteString)
                        .font(.footnote)
                        .foregroundStyle(palette.inkSecondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
        if model.outboxCount > 0 {
            RowRule()
            SettingsRow {
                Text("Waiting to sync")
                Spacer()
                Text(model.outboxCount == 1 ? "1 Position" : "\(model.outboxCount) Positions")
                    .foregroundStyle(palette.inkSecondary)
            }
        }
        RowRule()
        SignOutRow()
    }

    // MARK: Reading

    @ViewBuilder private var readingRows: some View {
        SettingsRow {
            Text("Font")
            Spacer()
            Picker("Font", selection: $reading.fontFamily) {
                ForEach(ReadingFonts.all, id: \.name) { font in
                    Text(font.name).tag(font.family)
                }
            }
            .labelsHidden()
        }
        RowRule()
        SettingsRow {
            Text("Text size")
            Spacer()
            Stepper(
                (reading.fontSize ?? 1).formatted(.percent.precision(.fractionLength(0))),
                value: Binding { reading.fontSize ?? 1 } set: { reading.fontSize = $0 },
                in: 0.6 ... 2.5,
                step: 0.1
            )
            .fixedSize()
            .foregroundStyle(palette.inkSecondary)
        }
        RowRule()
        SettingsRow {
            Text("Page color")
            Spacer()
            PaperSegments(
                selection: Binding { reading.theme ?? .light } set: { reading.theme = $0 },
                choices: [("Light", ReadiumNavigator.Theme.light), ("Sepia", .sepia), ("Dark", .dark)]
            )
        }
        RowRule()
        SettingsRow {
            Text("Layout")
            Spacer()
            PaperSegments(
                selection: Binding { reading.scroll ?? false } set: { reading.scroll = $0 },
                choices: [("Pages", false), ("Scroll", true)]
            )
        }
        RowRule()
        SettingsRow {
            Text("Margins")
            Spacer()
            Slider(
                value: Binding { reading.pageMargins ?? 1 } set: { reading.pageMargins = $0 },
                in: 0.5 ... 2.5,
                step: 0.25
            )
            .frame(maxWidth: 180)
            .accessibilityLabel("Margins")
        }
        RowRule()
        SettingsRow {
            Text("Pages side by side")
            Spacer()
            Picker("Pages side by side", selection: Binding { PageSpread(reading) } set: { $0.apply(to: &reading) }) {
                ForEach(PageSpread.allCases, id: \.self) { spread in
                    Text(spread.name).tag(spread)
                }
            }
            .labelsHidden()
        }
        .disabled(reading.scroll == true)
    }

    // MARK: Listening

    @ViewBuilder private var listeningRows: some View {
        SettingsRow {
            Text("Skip back")
            Spacer()
            skipPicker("Skip back", selection: $listening.skipBack)
        }
        RowRule()
        SettingsRow {
            Text("Skip forward")
            Spacer()
            skipPicker("Skip forward", selection: $listening.skipForward)
        }
        RowRule()
        SettingsRow {
            Text("Speed")
            Spacer()
            Picker("Speed", selection: $listening.speed) {
                ForEach(ListeningSettings.speeds, id: \.self) { speed in
                    Text("\(speed.formatted(.number.precision(.fractionLength(0 ... 2))))×").tag(speed)
                }
            }
            .labelsHidden()
        }
    }

    private func skipPicker(_ title: String, selection: Binding<Duration>) -> some View {
        Picker(title, selection: selection) {
            ForEach(ListeningSettings.skipChoices, id: \.self) { skip in
                Text("\(skip.components.seconds) seconds").tag(skip)
            }
        }
        .labelsHidden()
    }

    // MARK: Downloads

    @ViewBuilder private var downloads: some View {
        SettingsRow {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(DownloadsView.size(model.downloadList.totalBytes)) on this device")
                Text(model.downloadList.downloads.count == 1 ? "1 Book file" : "\(model.downloadList.downloads.count) Book files")
                    .font(.footnote)
                    .foregroundStyle(palette.inkSecondary)
            }
        }
        RowRule()
        Button { isShowingDownloads = true } label: {
            SettingsRow {
                Text("Manage Downloads")
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(palette.inkSecondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: About

    @ViewBuilder private var about: some View {
        SettingsRow {
            Text("Dogear")
            Spacer()
            Text(Self.appVersion).foregroundStyle(palette.inkSecondary)
        }
        RowRule()
        SettingsRow {
            Text("Grimmory")
            Spacer()
            Text(session.serverVersion ?? "Unknown").foregroundStyle(palette.inkSecondary)
        }
    }

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(version) (\($0))" } ?? version
    }
}

/// Signing out, with a warning that says what it will discard.
private struct SignOutRow: View {
    @Environment(AppModel.self) private var model
    @State private var isConfirming = false

    /// Downloads go too: another account or Server numbers its Books differently.
    private var warning: String {
        let again = "Signing in again needs your Server address and password."
        return switch (model.outboxCount > 0, !model.downloadList.downloads.isEmpty) {
        case (true, true): "Some of your reading progress hasn't reached your Server yet. Signing out discards it and removes your Downloads from this device."
        case (true, false): "Some of your reading progress hasn't reached your Server yet. Signing out discards it. \(again)"
        case (false, true): "Signing out removes your Downloads from this device. \(again)"
        case (false, false): "Signing out clears this device's copy of your library. \(again)"
        }
    }

    var body: some View {
        Button(role: .destructive) { isConfirming = true } label: {
            SettingsRow {
                Text("Sign Out…")
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.ribbon)
                Spacer()
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .confirmationDialog(warning, isPresented: $isConfirming, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) {
                Task { await model.signOut() }
            }
        }
    }
}

/// A heading on the canvas above its paper card.
private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    @Environment(\.palette) private var palette

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .serifTitle(20, relativeTo: .title3)
                .foregroundStyle(palette.text)
                .padding(.leading, 4)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) { content }
                .paperCard(radius: 12)
        }
        .padding(.top, 24)
    }
}

/// One line on a settings card.
private struct SettingsRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 10) { content }
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
    }
}

/// A faint pencil rule between rows.
private struct RowRule: View {
    @Environment(\.palette) private var palette

    var body: some View {
        palette.outline.opacity(0.6)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

/// A segmented choice on a settings card.
private struct PaperSegments<Value: Hashable>: View {
    @Binding var selection: Value
    let choices: [(name: String, value: Value)]

    var body: some View {
        Segments(selection: $selection, choices: choices, onPaper: true)
            .fixedSize()
    }
}

/// The three app themes as small pictures of each to tap. The chosen one has a check and an
/// accent frame; picking one changes the whole app at once.
private struct ThemeTiles: View {
    @Binding var selection: AppTheme

    @Environment(\.palette) private var palette

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
            ForEach(AppTheme.allCases, id: \.self) { theme in
                tile(theme)
            }
        }
        .padding(12)
        .sensoryFeedback(.selection, trigger: selection)
        .animation(.snappy(duration: 0.15), value: selection)
    }

    private func tile(_ theme: AppTheme) -> some View {
        let isOn = theme == selection
        return Button { selection = theme } label: {
            VStack(spacing: 8) {
                ThemePreview(palette: Palette(theme))
                    .frame(height: 96)
                    .accessibilityHidden(true)
                HStack(spacing: 4) {
                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isOn ? palette.paperAction : palette.inkSecondary)
                        .accessibilityHidden(true)
                    Text(theme.name)
                        .font(.footnote.weight(isOn ? .semibold : .regular))
                        .foregroundStyle(palette.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity)
            .background(isOn ? palette.accent.opacity(0.1) : .clear, in: .rect(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isOn ? palette.paperAction : palette.outline, lineWidth: isOn ? 2 : 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.name)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// A theme in miniature: its canvas, a paper card, a shelf of spines on its wood, and its accent.
private struct ThemePreview: View {
    let palette: Palette

    private static let spineHeights: [CGFloat] = [28, 32, 26, 30, 27]

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                palette.text.frame(width: 34, height: 5).clipShape(.capsule)
                palette.raised.frame(height: 9).clipShape(.capsule)
                    .overlay { Capsule().strokeBorder(palette.boundary, lineWidth: 0.5) }
                HStack(spacing: 2) {
                    palette.accent.frame(height: 7).clipShape(.capsule)
                    Capsule().strokeBorder(palette.boundary, lineWidth: 0.5).frame(height: 7)
                    Capsule().strokeBorder(palette.boundary, lineWidth: 0.5).frame(height: 7)
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.canvas)
            VStack(spacing: 0) {
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(Array(SpineColor.palette.prefix(5).enumerated()), id: \.offset) { index, color in
                        Color(color).frame(width: 9, height: Self.spineHeights[index])
                    }
                    Spacer(minLength: 0)
                    palette.shell.frame(width: 22, height: 16).clipShape(.rect(cornerRadius: 2))
                        .overlay { palette.shellTrim.frame(width: 14, height: 6).clipShape(.rect(cornerRadius: 1)) }
                }
                .padding(.horizontal, 6)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .background(palette.shelfBacking)
                palette.ledgeTop.frame(height: 2)
                palette.ledgeFace.frame(height: 4)
            }
        }
        .clipShape(.rect(cornerRadius: 6))
        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(.black.opacity(0.12), lineWidth: 1) }
    }
}
