import DogearCore
@preconcurrency import ReadiumNavigator
import SwiftUI

/// Everything the reader can set for the whole app: their account, the reader's defaults,
/// the player's skin and keys, Downloads and versions. Paper cards on the Library's felt, each named
/// by a leather tag.
struct SettingsView: View {
    let session: Session

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// The same values the reader's own sheet edits, so the two never disagree.
    @State private var reading = ReadingPreferences.load()
    @State private var listening = ListeningPreferences.load()
    /// The player reads the same key, so a new Player skin shows at once, even mid-listen.
    @AppStorage(ListeningPreferences.skinKey) private var storedSkin: String?
    @State private var isShowingDownloads = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Drawn here rather than as the navigation title, which a sheet letters in
                    // the system's black and loses on the felt.
                    Text("Settings")
                        .font(.largeTitle.bold())
                        .foregroundStyle(Theme.clothInk)
                        .shadow(color: .black.opacity(0.5), radius: 0, y: 1)
                        .padding(.horizontal, 4)
                        .padding(.top, 4)
                        .accessibilityAddTraits(.isHeader)
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
            .background { FeltBackground() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .tint(Theme.clothInk)
                }
            }
            .sheet(isPresented: $isShowingDownloads) { DownloadsView() }
        }
        // Dark chrome to match the felt; the paper cards set their own light appearance.
        .preferredColorScheme(.dark)
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
                    .foregroundStyle(Theme.clothInk)
                    .frame(width: 40, height: 40)
                    .background(Theme.bookCloth[0], in: .circle)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.username)
                    Text(session.server.host() ?? session.server.absoluteString)
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSoft)
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
                    .foregroundStyle(Theme.inkSoft)
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
            .foregroundStyle(Theme.inkSoft)
        }
        RowRule()
        SettingsRow {
            Text("Theme")
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
        SkinTiles(selection: Binding { PlayerSkin(stored: storedSkin) } set: { storedSkin = $0.rawValue })
        RowRule()
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
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        RowRule()
        Button { isShowingDownloads = true } label: {
            SettingsRow {
                Text("Manage Downloads")
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.inkSoft)
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
            Text(Self.appVersion).foregroundStyle(Theme.inkSoft)
        }
        RowRule()
        SettingsRow {
            Text("Grimmory")
            Spacer()
            Text(session.serverVersion ?? "Unknown").foregroundStyle(Theme.inkSoft)
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

/// A leather tag naming the section above its paper card.
private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ShelfLabel(title)
                .padding(.leading, 4)
            VStack(spacing: 0) { content }
                .background {
                    Theme.paper
                        .overlay {
                            RadialGradient(colors: [.white.opacity(0.4), .clear], center: .init(x: 0.25, y: 0.1), startRadius: 0, endRadius: 320)
                        }
                }
                .clipShape(.rect(cornerRadius: 4))
                .shadow(color: .black.opacity(0.5), radius: 5, y: 3)
                // Paper is light whatever the device's appearance, so its text is always ink.
                .environment(\.colorScheme, .light)
                .foregroundStyle(Theme.ink)
                .tint(Theme.tabLeather[0])
        }
        .padding(.top, 22)
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
    var body: some View {
        Theme.inkSoft.opacity(0.18)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

/// A segmented choice whose chosen segment is a leather tab sunk into the paper.
private struct PaperSegments<Value: Hashable>: View {
    @Binding var selection: Value
    let choices: [(name: String, value: Value)]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(choices, id: \.value) { choice in
                let isOn = choice.value == selection
                Button { selection = choice.value } label: {
                    Text(choice.name)
                        .font(.subheadline)
                        .foregroundStyle(isOn ? Theme.tabLetteringPressed : Theme.inkSoft)
                        .padding(.horizontal, 11)
                        .frame(minHeight: 30)
                        .background {
                            if isOn {
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(LinearGradient(colors: Theme.tabLeather, startPoint: .top, endPoint: .bottom))
                                    .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
                            }
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Theme.ink.opacity(0.12), in: .rect(cornerRadius: 7))
        .animation(.snappy(duration: 0.15), value: selection)
    }
}

/// The Player skins as small drawings of each player to tap; the chosen one sits in a leather
/// frame.
private struct SkinTiles: View {
    @Binding var selection: PlayerSkin

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Player")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                tile(.pocket, name: "Pocket player")
                tile(.hifi, name: "Hi-fi deck")
                tile(.turntable, name: "Turntable")
                tile(.radio, name: "Valve radio")
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .sensoryFeedback(.selection, trigger: selection)
        .animation(.snappy(duration: 0.15), value: selection)
    }

    private func tile(_ skin: PlayerSkin, name: String) -> some View {
        let isOn = skin == selection
        return Button { selection = skin } label: {
            VStack(spacing: 6) {
                SkinThumbnail(skin: skin)
                    .frame(height: 92)
                    .accessibilityHidden(true)
                Text(name)
                    .font(.subheadline.weight(isOn ? .semibold : .regular))
                    .foregroundStyle(isOn ? Theme.ink : Theme.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(isOn ? Theme.tabLeather[0].opacity(0.14) : Theme.ink.opacity(0.06), in: .rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isOn ? Theme.tabLeather[0] : .clear, lineWidth: 2)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// A small drawing of a Player skin: its body, its window and its keys.
private struct SkinThumbnail: View {
    let skin: PlayerSkin

    var body: some View {
        switch skin {
        case .pocket:
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(LinearGradient(colors: [Color(hex: 0x2A2C30), Color(hex: 0x0E0F11)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(Deck.trim, lineWidth: 2) }
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3).fill(Color(hex: 0xF7F3E8))
                    RoundedRectangle(cornerRadius: 3).fill(Deck.orange)
                    RoundedRectangle(cornerRadius: 3).fill(Color(hex: 0xF7F3E8))
                }
                .frame(height: 20)
            }
            .padding(10)
            .background(LinearGradient(colors: [Deck.bodyLight, Deck.bodyDark], startPoint: .top, endPoint: .bottom), in: .rect(cornerRadius: 6))
        case .hifi:
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Hifi.well)
                    .overlay { RoundedRectangle(cornerRadius: 3).strokeBorder(Hifi.bezel, lineWidth: 1.5) }
                Text("01:24:35")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Hifi.glow)
                    .shadow(color: Hifi.glow.opacity(0.8), radius: 3)
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                    .background(Hifi.display[0], in: .rect(cornerRadius: 3))
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3).fill(LinearGradient(colors: Hifi.key, startPoint: .top, endPoint: .bottom))
                    RoundedRectangle(cornerRadius: 3).fill(LinearGradient(colors: Hifi.key, startPoint: .top, endPoint: .bottom))
                        .frame(maxWidth: .infinity)
                        .layoutPriority(1)
                    RoundedRectangle(cornerRadius: 3).fill(LinearGradient(colors: Hifi.key, startPoint: .top, endPoint: .bottom))
                }
                .frame(height: 16)
            }
            .padding(10)
            .background(LinearGradient(colors: Hifi.panel, startPoint: .top, endPoint: .bottom), in: .rect(cornerRadius: 6))
        case .turntable:
            HStack(spacing: 0) {
                ZStack {
                    Circle().fill(Walnut.platter[1])
                    Circle().fill(Walnut.vinyl[1]).padding(3)
                    Circle().fill(Theme.ribbon).frame(width: 22, height: 22)
                }
                .frame(width: 70, height: 70)
                Capsule()
                    .fill(Walnut.platter[0])
                    .frame(width: 4, height: 62)
                    .rotationEffect(.degrees(28), anchor: .top)
                    .offset(x: -6, y: -2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(4)
            .background(LinearGradient(colors: Walnut.plinth, startPoint: .top, endPoint: .bottom), in: .rect(cornerRadius: 4))
            .padding(6)
            .background(LinearGradient(colors: Walnut.wood, startPoint: .top, endPoint: .bottom), in: .rect(cornerRadius: 6))
        case .radio:
            VStack(spacing: 6) {
                UnevenRoundedRectangle(topLeadingRadius: 24, bottomLeadingRadius: 3, bottomTrailingRadius: 3, topTrailingRadius: 24)
                    .fill(Bakelite.cloth)
                    .overlay {
                        HStack(spacing: 3) {
                            ForEach(0 ..< 12, id: \.self) { _ in Bakelite.brass.frame(width: 2) }
                        }
                    }
                    .overlay {
                        Circle().strokeBorder(Bakelite.eye, lineWidth: 4).frame(width: 16, height: 16)
                            .shadow(color: Bakelite.eye, radius: 4)
                    }
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 24, bottomLeadingRadius: 3, bottomTrailingRadius: 3, topTrailingRadius: 24))
                RoundedRectangle(cornerRadius: 3)
                    .fill(Bakelite.dialLight)
                    .overlay { Theme.ribbon.frame(width: 2).offset(x: -8) }
                    .frame(height: 20)
            }
            .padding(10)
            .background(LinearGradient(colors: Bakelite.body, startPoint: .top, endPoint: .bottom), in: .rect(cornerRadius: 6))
        }
    }
}
