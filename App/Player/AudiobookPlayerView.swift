import AVKit
import DogearCore
import SwiftUI

/// Full-screen player for one audiobook Book file, drawn in the listener's Player skin: the
/// pocket tape player or the hi-fi deck. Either way the Book is loaded as a cassette and the
/// tape on its reels is how far through the Book the listener is.
///
/// Closing it leaves the audiobook playing under the library; Eject stops it.
struct AudiobookPlayerView: View {
    @State var model: AudiobookPlayerModel
    let cover: Cover?
    let library: Library?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(AppModel.self) private var app
    @AppStorage(ListeningPreferences.skinKey) private var storedSkin: String?
    @State private var isShowingChapters = false
    @State private var isShowingTracks = false
    @State private var coverColors = CoverColors()

    private var skin: PlayerSkin { PlayerSkin(stored: storedSkin) }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    player
                        .padding(14)
                        // On a tall screen the player sits in the middle, not against the top.
                        .frame(minHeight: proxy.size.height, alignment: sizeClass == .regular ? .center : .top)
                }
                // Pulled down past the top, the player closes like a sheet, and the tape plays on.
                .modifier(PullsDownToClose(close: close))
            }
            .background { skinBackground.ignoresSafeArea() }
            // Each skin is its own plastic or metal whatever the device's appearance.
            .environment(\.colorScheme, skin == .pocket ? .light : .dark)
            .tint(tint)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isShowingChapters) {
                ChaptersView(model: model)
            }
            .sheet(isPresented: $isShowingTracks) {
                TracksView(model: model)
            }
            .task(id: cover) {
                if let library { await coverColors.load(cover, from: library) }
            }
        }
        // Every text size up to the largest accessibility ones would push the keys off the deck.
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }

    @ViewBuilder private var player: some View {
        switch skin {
        case .pocket: PocketPlayer(model: model, controls: controls)
        case .hifi: HifiDeck(model: model, controls: controls)
        case .turntable: TurntableDeck(model: model, controls: controls)
        case .radio: ValveRadio(model: model, controls: controls)
        }
    }

    @ViewBuilder private var skinBackground: some View {
        switch skin {
        case .pocket: PocketPlayer.background
        case .hifi: HifiDeck.background
        case .turntable: TurntableDeck.background
        case .radio: ValveRadio.background
        }
    }

    private var tint: Color {
        switch skin {
        case .pocket: Deck.orange
        case .hifi: Hifi.glow
        case .turntable: Walnut.brass
        case .radio: Bakelite.dialLight
        }
    }

    private var controls: PlayerControls {
        PlayerControls(
            stripe: Color(coverColors.color(of: cover) ?? SpineColor.palette[1]),
            close: close,
            showContents: {
                if model.info?.isFolder == true { isShowingTracks = true } else { isShowingChapters = true }
            }
        )
    }

    /// Leaves the tape running under the library, or ejects one that can't play, so no strip is
    /// left behind for it.
    private func close() {
        if case .failed = model.state {
            Task { await app.eject() }
        } else {
            dismiss()
        }
    }

    static func format(speed: Float) -> String {
        speed.formatted(.number.precision(.fractionLength(0 ... 2))) + "×"
    }

    /// Always hours, minutes and seconds, like a counter's fixed wheels.
    static func wheels(_ seconds: Double) -> String {
        let whole = Int(seconds.rounded(.down))
        return String(format: "%02d:%02d:%02d", whole / 3600, whole / 60 % 60, whole % 60)
    }

    static func format(_ seconds: Double) -> String {
        Duration.seconds(seconds.rounded(.down)).formatted(.time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }
}

/// What a Player skin needs from the player around it, beyond the model.
struct PlayerControls {
    /// The cassette label's stripe, from the Book's cover.
    let stripe: Color
    /// Closes the player and leaves the tape running.
    let close: () -> Void
    /// Opens the Chapters, or the Tracks of a folder audiobook.
    let showContents: () -> Void
}

/// What every Player skin shows the same way.
extension AudiobookPlayerModel {
    /// Whole-book length in seconds, never zero so it can divide.
    var bookSeconds: Double { max(info?.duration.seconds ?? 1, 1) }

    /// The Chapter or Track playing.
    var placeName: String? { chapter?.title ?? track.map(TracksView.title) }

    /// Folder audiobooks list Tracks; the rest list Chapters.
    var contentsName: String { info?.isFolder == true ? "Tracks" : "Chapters" }
    var contentsIcon: String { info?.isFolder == true ? "list.number" : "list.bullet" }
    var hasContents: Bool {
        info?.isFolder == true ? !(info?.tracks.isEmpty ?? true) : !(info?.chapters.isEmpty ?? true)
    }

    var sleepLabel: String {
        guard let timer = sleepTimer else { return "Off" }
        if let remaining = timer.remaining { return AudiobookPlayerView.format(remaining.seconds.rounded(.up)) }
        return "Chapter end"
    }
}

/// The sleep timer's choices, for a skin's menu.
struct SleepTimerChoices: View {
    let model: AudiobookPlayerModel

    var body: some View {
        if model.sleepTimer != nil {
            Button("Turn Off", systemImage: "moon.zzz") { model.setSleepTimer(nil) }
        }
        Button("End of Chapter") { model.setSleepTimer(.endOfChapter) }
        ForEach([5, 15, 30, 45, 60], id: \.self) { minutes in
            Button("\(minutes) minutes") { model.setSleepTimer(.after(.seconds(minutes * 60))) }
        }
    }
}

/// The player folded down to a strip under the library while its audiobook is loaded, in the
/// Player skin's materials. A tap opens the player again; the key plays and pauses without
/// opening it.
struct NowPlayingBar: View {
    let player: AudiobookPlayerModel
    let open: () -> Void

    @Environment(AppModel.self) private var app
    @AppStorage(ListeningPreferences.skinKey) private var storedSkin: String?

    private var look: StripLook { StripLook(PlayerSkin(stored: storedSkin)) }

    private var detail: String? {
        player.placeName ?? player.author
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: open) {
                HStack(spacing: 10) {
                    Image(systemName: look.icon)
                        .font(.title2)
                        .foregroundStyle(look.print)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(look.isDisplay ? player.title.uppercased() : player.title)
                            .font(look.titleFont)
                            .foregroundStyle(look.title)
                            .shadow(color: look.isDisplay ? look.title.opacity(0.6) : .clear, radius: 4)
                        if let detail {
                            Text(detail)
                                .font(.system(.caption, weight: .bold).width(.condensed))
                                .foregroundStyle(look.print)
                        }
                    }
                    .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens the player")
            Button(player.isPlaying ? "Pause" : "Play", systemImage: player.isPlaying ? "pause.fill" : "play.fill") {
                player.togglePlayback()
            }
            .labelStyle(.iconOnly)
            .font(.title3)
            .foregroundStyle(look.keyLettering)
            .frame(width: 44, height: 44)
            .background(LinearGradient(colors: look.key, startPoint: .top, endPoint: .bottom), in: .circle)
            .disabled(!isReady)
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .background(LinearGradient(colors: look.body, startPoint: .top, endPoint: .bottom), in: .rect(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(look.trim, lineWidth: 1) }
        .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
        .contextMenu {
            Button("Eject", systemImage: "eject.fill") { Task { await app.eject() } }
        }
        .accessibilityAction(named: "Eject") { Task { await app.eject() } }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
        // The skin's own materials whatever the device's appearance, like the player.
        .environment(\.colorScheme, look.scheme)
    }

    private var isReady: Bool {
        if case .ready = player.state { true } else { false }
    }
}

/// How the now-playing strip is drawn for each Player skin.
private struct StripLook {
    let body: [Color]
    let trim: Color
    let icon: String
    let title: Color
    let titleFont: Font
    /// Lettered like a glowing display rather than a label.
    let isDisplay: Bool
    let print: Color
    let key: [Color]
    let keyLettering: Color
    let scheme: ColorScheme

    init(_ skin: PlayerSkin) {
        switch skin {
        case .pocket:
            body = [Deck.bodyLight, Deck.bodyDark]
            trim = Deck.trim
            icon = "recordingtape"
            title = Theme.pen
            titleFont = Theme.label(.subheadline)
            isDisplay = false
            print = Deck.print.opacity(0.85)
            key = [Color(hex: 0xF0692B), Color(hex: 0xC9460F)]
            keyLettering = .white
            scheme = .light
        case .hifi:
            body = Hifi.panel
            trim = Hifi.bezel
            icon = "recordingtape"
            title = Hifi.glow
            titleFont = .system(.subheadline, design: .monospaced, weight: .semibold)
            isDisplay = true
            print = Hifi.print
            key = Hifi.key
            keyLettering = Hifi.lettering
            scheme = .dark
        case .turntable:
            body = Walnut.wood
            trim = Walnut.brassEdge
            icon = "opticaldisc"
            title = Theme.paper
            titleFont = .system(.subheadline, design: .serif, weight: .bold)
            isDisplay = false
            print = Walnut.print
            key = Walnut.brassFace
            keyLettering = Theme.ink
            scheme = .dark
        case .radio:
            body = Bakelite.body
            trim = Bakelite.brass
            icon = "radio"
            title = Bakelite.cream
            titleFont = .system(.subheadline, design: .serif, weight: .bold)
            isDisplay = false
            print = Bakelite.cream.opacity(0.85)
            key = Bakelite.ivory
            keyLettering = Theme.ink
            scheme = .dark
        }
    }
}

/// The system's AirPlay and Bluetooth route picker.
struct RoutePicker: UIViewRepresentable {
    /// The icon's colour while playing somewhere other than the device.
    var activeTint: UIColor = .systemOrange

    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = false
        picker.tintColor = .white
        picker.activeTintColor = activeTint
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

private struct ChaptersView: View {
    let model: AudiobookPlayerModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(model.info?.chapters ?? []) { chapter in
                Button {
                    model.go(to: chapter)
                    dismiss()
                } label: {
                    HStack {
                        Text(chapter.title)
                            .font(.body)
                        Spacer()
                        if chapter == model.chapter {
                            Image(systemName: "speaker.wave.2.fill")
                                .foregroundStyle(.tint)
                                .accessibilityLabel("Playing")
                        }
                        Text(AudiobookPlayerView.format(chapter.start.seconds))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .foregroundStyle(Theme.pen)
                // The Chapter playing is run over with a highlighter.
                .listRowBackground(chapter == model.chapter ? Color(hex: 0xFFE45C) : Theme.paper)
            }
            // The cassette's paper insert: handwriting on paper, light whatever the appearance.
            .scrollContentBackground(.hidden)
            .background(Theme.paper)
            .environment(\.colorScheme, .light)
            .tint(Deck.orange)
            .navigationTitle("Chapters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct TracksView: View {
    let model: AudiobookPlayerModel
    @Environment(\.dismiss) private var dismiss

    static func title(_ track: AudiobookInfo.Track) -> String {
        track.title ?? "Track \(track.index + 1)"
    }

    var body: some View {
        NavigationStack {
            List(model.info?.tracks ?? []) { track in
                Button {
                    model.go(to: track)
                    dismiss()
                } label: {
                    HStack {
                        Text(Self.title(track))
                            .font(.body)
                        Spacer()
                        if track == model.track {
                            Image(systemName: "speaker.wave.2.fill")
                                .foregroundStyle(.tint)
                                .accessibilityLabel("Playing")
                        }
                        Text(AudiobookPlayerView.format(track.duration.seconds))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .foregroundStyle(Theme.pen)
                // The Track playing is run over with a highlighter.
                .listRowBackground(track == model.track ? Color(hex: 0xFFE45C) : Theme.paper)
            }
            // The cassette's paper insert: handwriting on paper, light whatever the appearance.
            .scrollContentBackground(.hidden)
            .background(Theme.paper)
            .environment(\.colorScheme, .light)
            .tint(Deck.orange)
            .navigationTitle("Tracks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// The cassette behind the player's door. Its reels show the Position and its hubs turn while
/// the tape runs.
struct LoadedCassette: View {
    static let size = CGSize(width: 300, height: 188)

    let title: String
    let author: String?
    let stripe: Color
    /// 0…1.
    let throughBook: Double
    let isPlaying: Bool
    let speed: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let reels = TapeReels(throughBook: throughBook, hub: 11, full: 30)
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 9)
                .fill(LinearGradient(colors: [Color(hex: 0x34353A), Color(hex: 0x1C1D20)], startPoint: .top, endPoint: .bottom))
            VStack(spacing: 0) {
                Theme.paper
                Deck.orange.frame(height: 9)
                Theme.paper.frame(height: 5)
                stripe.frame(height: 18)
            }
            .frame(height: 122)
            .clipShape(.rect(cornerRadius: 4))
            .padding(.horizontal, 12)
            .padding(.top, 10)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(Theme.cassetteLabel(19))
                    .foregroundStyle(Theme.pen)
                if let author {
                    Text(author)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.inkSoft)
                }
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 14)
            TimelineView(.animation(paused: !isPlaying || reduceMotion)) { timeline in
                // One turn every 2.4 s at 1×, faster with the speed.
                let angle = Angle.degrees(timeline.date.timeIntervalSinceReferenceDate * 150 * speed)
                ZStack {
                    LinearGradient(colors: [Color(hex: 0x120D0A), Color(hex: 0x3A2A20)], startPoint: .top, endPoint: .bottom)
                    reel(tape: reels.supply, angle: angle).offset(x: -48)
                    reel(tape: reels.takeUp, angle: angle).offset(x: 48)
                }
            }
            .frame(width: 176, height: 50)
            .clipShape(.rect(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.paper, lineWidth: 2) }
            .padding(.top, 64)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    private func reel(tape radius: Double, angle: Angle) -> some View {
        ZStack {
            Circle().fill(Theme.tape).frame(width: radius * 2, height: radius * 2)
            Circle().fill(.white).frame(width: 22, height: 22)
            ForEach(0 ..< 3, id: \.self) { tooth in
                Capsule().fill(Color(hex: 0x2A1A10)).frame(width: 3, height: 18).rotationEffect(.degrees(Double(tooth) * 60))
            }
            .rotationEffect(-angle)
        }
    }
}
