import AVKit
import DogearCore
import SwiftUI

/// Full-screen player for one audiobook Book file, as a pocket tape player with the Book loaded
/// as a cassette. The tape on the reels is how far through the Book the listener is.
struct AudiobookPlayerView: View {
    @State var model: AudiobookPlayerModel
    let cover: Cover?
    let library: Library?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var isShowingChapters = false
    @State private var isShowingTracks = false
    @State private var scrubbing: Double?
    @State private var coverColors = CoverColors()
    /// How much the cassette shrinks to fit a narrow door.
    @State private var cassetteScale: CGFloat = 1

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    content
                        .padding(14)
                        // On a tall screen the player sits in the middle, not against the top.
                        .frame(minHeight: proxy.size.height, alignment: sizeClass == .regular ? .center : .top)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .background {
                LinearGradient(colors: [Deck.bodyLight, Deck.bodyDark], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            }
            // The player's body is cream plastic whatever the device's appearance.
            .environment(\.colorScheme, .light)
            .tint(Deck.orange)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isShowingChapters) {
                ChaptersView(model: model)
            }
            .sheet(isPresented: $isShowingTracks) {
                TracksView(model: model)
            }
            .task { await model.open() }
            .task(id: cover) {
                if let library { await coverColors.load(cover, from: library) }
            }
            .onDisappear { Task { await model.close() } }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await model.catchUp() } }
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .opening:
            VStack(spacing: 14) {
                topBar
                door { ProgressView("Opening…").tint(.white).foregroundStyle(.white) }
            }
        case let .failed(message):
            VStack(spacing: 14) {
                topBar
                door { EmptyView() }
                ContentUnavailableView("Can't play this audiobook", systemImage: "exclamationmark.triangle", description: Text(message))
            }
        case .ready:
            if sizeClass == .regular {
                // Cassette beside the controls, using the iPad's width.
                VStack(spacing: 14) {
                    topBar
                    HStack(alignment: .top, spacing: 32) {
                        VStack(spacing: 14) {
                            door { cassette }
                            chapterStrip
                            problemNote
                            counter
                        }
                        .frame(maxWidth: 440)
                        VStack(spacing: 14) {
                            scrubber
                            transport
                            speedSlider
                            outputs
                        }
                        .frame(maxWidth: 440)
                    }
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 14) {
                    topBar
                    door { cassette }
                    chapterStrip
                    problemNote
                    counter
                    scrubber
                    transport
                    speedSlider
                    outputs
                }
            }
        }
    }

    private var elapsed: Double { scrubbing ?? model.currentTime.seconds }
    private var duration: Double { max(model.info?.duration.seconds ?? 1, 1) }

    /// Eject closes the player; Chapters opens the cassette's insert.
    private var topBar: some View {
        HStack {
            Button("Eject", systemImage: "eject.fill") { dismiss() }
                .buttonStyle(CapStyle())
                .accessibilityLabel("Close")
            Spacer()
            Text("DOGEAR")
                .font(.system(size: 16, weight: .bold).width(.condensed))
                .tracking(5)
                .foregroundStyle(Deck.print)
                .accessibilityHidden(true)
            Spacer()
            if model.info?.isFolder == true {
                Button("Tracks", systemImage: "list.number") { isShowingTracks = true }
                    .buttonStyle(CapStyle())
                    .disabled(model.info?.tracks.isEmpty ?? true)
            } else {
                Button("Chapters", systemImage: "list.bullet") { isShowingChapters = true }
                    .buttonStyle(CapStyle())
                    .disabled(model.info?.chapters.isEmpty ?? true)
            }
        }
    }

    /// The tinted window the cassette sits behind.
    private func door(@ViewBuilder _ loaded: () -> some View) -> some View {
        LinearGradient(colors: [Color(hex: 0x2A2C30), Color(hex: 0x0E0F11)], startPoint: .topLeading, endPoint: .bottomTrailing)
            .frame(height: 220)
            .overlay { loaded() }
            .clipShape(.rect(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(Deck.trim, lineWidth: 3) }
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { width in
                cassetteScale = min(1, (width - 28) / LoadedCassette.size.width)
            }
    }

    private var cassette: some View {
        LoadedCassette(
            title: model.title, author: model.author,
            stripe: Color(coverColors.color(of: cover) ?? SpineColor.palette[1]),
            throughBook: elapsed / duration, isPlaying: model.isPlaying, speed: Double(model.speed)
        )
        .scaleEffect(cassetteScale)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([model.title, model.author].compactMap { $0 }.joined(separator: ", "))
    }

    /// The Chapter or Track playing, on embossed label tape.
    private var chapterStrip: some View {
        Text((model.chapter?.title ?? model.track.map(TracksView.title) ?? " ").uppercased())
            .font(.system(size: 14, weight: .bold).width(.condensed))
            .tracking(2)
            .lineLimit(1)
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(LinearGradient(colors: [Color(hex: 0x2A2A2C), Color(hex: 0x111111)], startPoint: .top, endPoint: .bottom), in: .rect(cornerRadius: 3))
            .rotationEffect(.degrees(-0.6))
    }

    @ViewBuilder private var problemNote: some View {
        if let problem = model.problem {
            Label(problem, systemImage: "exclamationmark.triangle")
                .font(Theme.hand(14))
                .foregroundStyle(Theme.ink)
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(Color(hex: 0xFFE98A), in: .rect(cornerRadius: 2))
                .rotationEffect(.degrees(0.8))
        }
    }

    /// Whole-book time on a mechanical counter, with what's left of the tape beside it.
    private var counter: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                DeckLabel("Tape counter")
                HStack(spacing: 2) {
                    ForEach(Array(Self.wheels(elapsed).enumerated()), id: \.offset) { _, character in
                        Text(String(character))
                            .font(.system(size: 22, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color(hex: 0xF4F1E8))
                            .frame(width: character == ":" ? 8 : 20, height: 30)
                            .background(character == ":" ? Color.clear : Color(hex: 0x161616), in: .rect(cornerRadius: 2))
                    }
                }
                .padding(4)
                .background(.black, in: .rect(cornerRadius: 4))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Elapsed \(Self.format(elapsed))")
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                DeckLabel("Tape left")
                Text("-" + Self.wheels(max(0, duration - elapsed)))
                    .font(.system(size: 22, weight: .medium, design: .monospaced))
                    .foregroundStyle(Deck.print)
                    .frame(height: 38)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Remaining \(Self.format(max(0, duration - elapsed)))")
        }
    }

    /// Whole-book time; Chapters are in the list.
    private var scrubber: some View {
        Slider(
            value: Binding { elapsed } set: { scrubbing = $0 },
            in: 0 ... duration
        ) { editing in
            if !editing, let scrubbing {
                model.seek(to: .seconds(scrubbing))
                self.scrubbing = nil
            }
        }
        .accessibilityLabel("Position")
        .accessibilityValue(Self.format(elapsed))
    }

    private var transport: some View {
        HStack(spacing: 8) {
            Button {
                model.skip(by: .zero - AudiobookPlayerModel.skipBack)
            } label: {
                KeyLabel(systemImage: "backward.fill", text: "\(Int(AudiobookPlayerModel.skipBack.seconds)) SEC")
            }
            .buttonStyle(KeyStyle())
            .accessibilityLabel("Back \(Int(AudiobookPlayerModel.skipBack.seconds)) seconds")
            Button {
                model.togglePlayback()
            } label: {
                KeyLabel(systemImage: model.isPlaying ? "pause.fill" : "play.fill", text: model.isPlaying ? "PAUSE" : "PLAY")
            }
            // A tape player's play key stays down while the tape runs.
            .buttonStyle(KeyStyle(isMain: true, isDown: model.isPlaying))
            .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
            Button {
                model.skip(by: AudiobookPlayerModel.skipForward)
            } label: {
                KeyLabel(systemImage: "forward.fill", text: "\(Int(AudiobookPlayerModel.skipForward.seconds)) SEC")
            }
            .buttonStyle(KeyStyle())
            .accessibilityLabel("Forward \(Int(AudiobookPlayerModel.skipForward.seconds)) seconds")
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .background(LinearGradient(colors: [Color(hex: 0xA9A190), Color(hex: 0x8C8473)], startPoint: .top, endPoint: .bottom), in: .rect(cornerRadius: 10))
        .sensoryFeedback(.impact, trigger: model.isPlaying)
    }

    /// One detent for each speed; the knob sits on the one in use.
    private var speedSlider: some View {
        VStack(spacing: 2) {
            HStack {
                DeckLabel("Speed")
                Spacer()
                DeckLabel(Self.format(speed: model.speed))
            }
            HStack(spacing: 0) {
                ForEach(AudiobookPlayerModel.speeds, id: \.self) { speed in
                    Button {
                        model.setSpeed(speed)
                    } label: {
                        VStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(LinearGradient(colors: [Deck.orangeDark, Deck.orange, Deck.orangeDark], startPoint: .leading, endPoint: .trailing))
                                .frame(width: 18, height: 26)
                                .shadow(color: .black.opacity(0.45), radius: 2, y: 2)
                                .opacity(speed == model.speed ? 1 : 0)
                            Text(speed.formatted(.number.precision(.fractionLength(0 ... 2))))
                                .font(.system(size: 11, weight: .bold).width(.condensed))
                                .foregroundStyle(Deck.print)
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Speed \(Self.format(speed: speed))")
                    .accessibilityAddTraits(speed == model.speed ? .isSelected : [])
                }
            }
            .background(alignment: .top) {
                // The slot the knob slides in.
                Capsule().fill(Color(hex: 0x17120E)).frame(height: 6).padding(.horizontal, 16).padding(.top, 12)
            }
            .sensoryFeedback(.selection, trigger: model.speed)
        }
    }

    private var outputs: some View {
        HStack {
            HStack(spacing: 8) {
                RoutePicker()
                    .frame(width: 44, height: 44)
                    .background(Color(hex: 0x3A3A3D), in: .circle)
                DeckLabel("Output")
            }
            Spacer()
            sleepMenu
        }
    }

    private var sleepMenu: some View {
        Menu {
            if model.sleepTimer != nil {
                Button("Turn Off", systemImage: "moon.zzz") { model.setSleepTimer(nil) }
            }
            Button("End of Chapter") { model.setSleepTimer(.endOfChapter) }
            ForEach([5, 15, 30, 45, 60], id: \.self) { minutes in
                Button("\(minutes) minutes") { model.setSleepTimer(.after(.seconds(minutes * 60))) }
            }
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .trailing, spacing: 2) {
                    DeckLabel("Sleep timer")
                    Text(sleepLabel)
                        .font(.system(size: 14, weight: .bold).width(.condensed))
                        .monospacedDigit()
                        .foregroundStyle(Deck.print)
                }
                // A dial whose pointer leaves "off" once a timer is set.
                Circle()
                    .fill(Color(hex: 0x2A2A2C))
                    .frame(width: 44, height: 44)
                    .overlay(alignment: .top) {
                        Capsule().fill(Deck.orange).frame(width: 4, height: 13).padding(.top, 4)
                    }
                    .rotationEffect(.degrees(model.sleepTimer == nil ? -120 : 30))
                    .shadow(color: .black.opacity(0.45), radius: 3, y: 3)
            }
        }
        .accessibilityLabel(model.sleepTimer == nil ? "Sleep timer" : "Sleep timer, \(sleepLabel)")
    }

    private var sleepLabel: String {
        guard let timer = model.sleepTimer else { return "Off" }
        if let remaining = timer.remaining { return Self.format(remaining.seconds.rounded(.up)) }
        return "Chapter end"
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

/// The system's AirPlay and Bluetooth route picker.
private struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = false
        picker.tintColor = .white
        picker.activeTintColor = .systemOrange
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
                            .font(Theme.hand(16))
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

private struct TracksView: View {
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
                            .font(Theme.hand(16))
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

/// The pocket player's plastic, print and keys.
private enum Deck {
    static let bodyLight = Color(hex: 0xEFE9D8)
    static let bodyDark = Color(hex: 0xD9D1BC)
    static let trim = Color(hex: 0xBDB5A0)
    /// Text printed on the body.
    static let print = Color(hex: 0x2B2620)
    static let orange = Color(hex: 0xE2571C)
    static let orangeDark = Color(hex: 0xB03D0C)
}

/// Small print naming a control.
private struct DeckLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold).width(.condensed))
            .tracking(1.5)
            .foregroundStyle(Deck.print.opacity(0.85))
    }
}

/// A small dark button on the top edge.
private struct CapStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold).width(.condensed))
            .textCase(.uppercase)
            .foregroundStyle(Color(hex: 0xF1ECE0))
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(LinearGradient(colors: [Color(hex: 0x3A3A3D), Color(hex: 0x1D1D1F)], startPoint: .top, endPoint: .bottom), in: .rect(cornerRadius: 8))
            .opacity(isEnabled ? 1 : 0.4)
            .offset(y: configuration.isPressed ? 2 : 0)
    }
}

private struct KeyLabel: View {
    let systemImage: String
    let text: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage).font(.system(size: 22))
            Text(text).font(.system(size: 11, weight: .bold).width(.condensed)).tracking(1.5)
        }
    }
}

/// A chunky piano key. The main key is orange and can stay down.
private struct KeyStyle: ButtonStyle {
    var isMain = false
    var isDown = false

    func makeBody(configuration: Configuration) -> some View {
        let down = isDown || configuration.isPressed
        let face = isMain ? [Color(hex: 0xF0692B), Color(hex: 0xC9460F)] : [Color(hex: 0xF7F3E8), Color(hex: 0xCFC7B3)]
        let edge = isMain ? Color(hex: 0x7A2A08) : Color(hex: 0x8C8473)
        configuration.label
            .foregroundStyle(isMain ? .white : Deck.print)
            .frame(maxWidth: .infinity, minHeight: 84)
            .background {
                UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 10, bottomTrailingRadius: 10, topTrailingRadius: 6)
                    .fill(LinearGradient(colors: face, startPoint: .top, endPoint: .bottom))
                    // The key's front edge, which disappears as it goes down.
                    .shadow(color: edge, radius: 0, y: down ? 1 : 6)
            }
            .offset(y: down ? 5 : 0)
            .animation(.snappy(duration: 0.12), value: down)
    }
}

/// The cassette behind the player's door. Its reels show the Position and its hubs turn while
/// the tape runs.
private struct LoadedCassette: View {
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
                    .font(Theme.marker(19))
                    .foregroundStyle(Theme.pen)
                if let author {
                    Text(author)
                        .font(.custom("Noteworthy-Light", fixedSize: 13))
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
