import DogearCore
import SwiftUI

/// The hi-fi deck skin: brushed black metal, the Book loaded as a cassette in a glass-fronted
/// well, a glowing display with the counter, time left and level meters, soft transport keys
/// and turned knobs for speed and sleep.
struct HifiDeck: View {
    let model: AudiobookPlayerModel
    let controls: PlayerControls

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(AppModel.self) private var app
    @State private var scrubbing: Double?
    /// How much the cassette shrinks to fit a narrow well.
    @State private var cassetteScale: CGFloat = 1

    /// Under the whole deck, filling the screen.
    static var background: some View {
        LinearGradient(colors: Hifi.panel, startPoint: .top, endPoint: .bottom)
            .overlay { BrushedMetal() }
    }

    var body: some View {
        switch model.state {
        case .opening:
            VStack(spacing: 14) {
                topBar
                well { ProgressView("Opening…").tint(Hifi.glow).foregroundStyle(Hifi.glow) }
            }
        case let .failed(message):
            VStack(spacing: 14) {
                topBar
                well { EmptyView() }
                ContentUnavailableView("Can't play this audiobook", systemImage: "exclamationmark.triangle", description: Text(message))
            }
        case .ready:
            if sizeClass == .regular {
                // Cassette and display beside the controls, using the iPad's width.
                VStack(spacing: 14) {
                    topBar
                    HStack(alignment: .top, spacing: 32) {
                        VStack(spacing: 14) {
                            well { cassette }
                            display
                            problemNote
                        }
                        .frame(maxWidth: 440)
                        VStack(spacing: 14) {
                            fader
                            transport
                            knobs
                        }
                        .frame(maxWidth: 440)
                    }
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 14) {
                    topBar
                    well { cassette }
                    display
                    problemNote
                    fader
                    transport
                    knobs
                }
            }
        }
    }

    private var elapsed: Double { scrubbing ?? model.currentTime.seconds }
    private var duration: Double { model.bookSeconds }
    private var speedName: String { AudiobookPlayerView.format(speed: model.speed) }

    /// Close leaves the tape running under the library; Eject stops it.
    private var topBar: some View {
        HStack(spacing: 8) {
            Button("Close", systemImage: "chevron.down", action: controls.close)
                .labelStyle(.iconOnly)
                .buttonStyle(SoftKeyStyle())
                .accessibilityHint("Keeps playing")
            Button("Eject", systemImage: "eject.fill") { Task { await app.eject() } }
                .buttonStyle(SoftKeyStyle())
                .accessibilityHint("Stops playing and closes the player")
            Spacer()
            VStack(spacing: 2) {
                Text("DOGEAR")
                    .font(.system(size: 16, weight: .bold).width(.condensed))
                    .tracking(5)
                    .foregroundStyle(Hifi.lettering)
                Text("STEREO CASSETTE DECK")
                    .font(.system(size: 8, weight: .semibold).width(.condensed))
                    .tracking(1.5)
                    .foregroundStyle(Hifi.print)
            }
            .lineLimit(1)
            .fixedSize()
            .accessibilityHidden(true)
            Spacer()
            Button(model.contentsName, systemImage: model.contentsIcon, action: controls.showContents)
                .buttonStyle(SoftKeyStyle())
                .disabled(!model.hasContents)
        }
    }

    /// The recess the cassette sits in, behind smoked glass.
    private func well(@ViewBuilder _ loaded: () -> some View) -> some View {
        Hifi.well
            .frame(height: 210)
            .overlay { loaded() }
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.14), location: 0),
                        .init(color: .white.opacity(0.14), location: 0.24),
                        .init(color: .clear, location: 0.25),
                        .init(color: .clear, location: 0.62),
                        .init(color: .white.opacity(0.05), location: 0.63),
                        .init(color: .white.opacity(0.05), location: 0.72),
                        .init(color: .clear, location: 0.73),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .clipShape(.rect(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(Hifi.bezel, lineWidth: 2) }
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { width in
                cassetteScale = min(1, (width - 28) / LoadedCassette.size.width)
            }
    }

    private var cassette: some View {
        LoadedCassette(
            title: model.title, author: model.author,
            stripe: controls.stripe,
            throughBook: elapsed / duration, isPlaying: model.isPlaying, speed: Double(model.speed)
        )
        .scaleEffect(cassetteScale)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([model.title, model.author].compactMap { $0 }.joined(separator: ", "))
    }

    /// The glowing display: the Chapter or Track playing, whole-book time and what's left, the
    /// tape's progress, level meters, and the deck's state.
    private var display: some View {
        VStack(alignment: .leading, spacing: 10) {
            Glowing((model.placeName ?? model.title).uppercased(), font: .system(.subheadline, design: .monospaced))
                .lineLimit(1)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .lastTextBaseline) {
                    elapsedReadout
                    Spacer(minLength: 8)
                    remainingReadout
                }
                VStack(alignment: .leading, spacing: 6) {
                    elapsedReadout
                    remainingReadout
                }
            }
            Segments(lit: elapsed / duration)
            LevelMeters(isPlaying: model.isPlaying)
            // The keys and knobs say all of this to VoiceOver.
            HStack {
                Glowing(model.isPlaying ? "PLAY" : "PAUSE", font: .system(.caption, design: .monospaced))
                Spacer(minLength: 6)
                Glowing("SPEED \(speedName)", font: .system(.caption, design: .monospaced))
                Spacer(minLength: 6)
                Glowing("SLEEP \(model.sleepLabel.uppercased())", font: .system(.caption, design: .monospaced))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: Hifi.display, startPoint: .top, endPoint: .bottom), in: .rect(cornerRadius: 6))
        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(Hifi.bezel, lineWidth: 2) }
    }

    private var elapsedReadout: some View {
        Glowing(AudiobookPlayerView.wheels(elapsed), font: .system(.largeTitle, design: .monospaced))
            .accessibilityLabel("Elapsed \(AudiobookPlayerView.format(elapsed))")
    }

    private var remainingReadout: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Glowing("REMAIN", font: .system(.caption2, design: .monospaced))
                .opacity(0.8)
            Glowing("-" + AudiobookPlayerView.wheels(max(0, duration - elapsed)), font: .system(.title3, design: .monospaced))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Remaining \(AudiobookPlayerView.format(max(0, duration - elapsed)))")
    }

    @ViewBuilder private var problemNote: some View {
        if let problem = model.problem {
            Label(problem, systemImage: "exclamationmark.triangle")
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(Hifi.amber)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Hifi.well, in: .rect(cornerRadius: 6))
                .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(Hifi.amber.opacity(0.5), lineWidth: 1) }
        }
    }

    /// A slide fader across the whole Book; Chapters are in the list. VoiceOver gets a slider.
    private var fader: some View {
        GeometryReader { proxy in
            let travel = max(proxy.size.width - 14, 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Hifi.well)
                    .frame(height: 6)
                    .overlay { Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5) }
                RoundedRectangle(cornerRadius: 3)
                    .fill(LinearGradient(colors: Hifi.faderCap, startPoint: .leading, endPoint: .trailing))
                    .frame(width: 14, height: 32)
                    .shadow(color: .black.opacity(0.6), radius: 3, y: 3)
                    .offset(x: CGFloat(elapsed / duration) * travel)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        scrubbing = min(max(Double((value.location.x - 7) / travel), 0), 1) * duration
                    }
                    .onEnded { _ in
                        if let scrubbing {
                            model.seek(to: .seconds(scrubbing))
                            self.scrubbing = nil
                        }
                    }
            )
        }
        .frame(height: 44)
        .accessibilityRepresentation {
            Slider(value: Binding { elapsed } set: { model.seek(to: .seconds($0)) }, in: 0 ... duration)
                .accessibilityLabel("Position")
                .accessibilityValue(AudiobookPlayerView.format(elapsed))
        }
    }

    private var transport: some View {
        HStack(spacing: 10) {
            Button {
                model.skip(by: .zero - model.skipBack)
            } label: {
                TransportLabel(systemImage: "backward.fill", text: "\(Int(model.skipBack.seconds)) sec", isLit: false)
            }
            .accessibilityLabel("Back \(Int(model.skipBack.seconds)) seconds")
            Button {
                model.togglePlayback()
            } label: {
                TransportLabel(systemImage: model.isPlaying ? "pause.fill" : "play.fill", text: model.isPlaying ? "Pause" : "Play", isLit: model.isPlaying)
            }
            .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
            Button {
                model.skip(by: model.skipForward)
            } label: {
                TransportLabel(systemImage: "forward.fill", text: "\(Int(model.skipForward.seconds)) sec", isLit: false)
            }
            .accessibilityLabel("Forward \(Int(model.skipForward.seconds)) seconds")
        }
        .buttonStyle(SoftKeyStyle())
        .sensoryFeedback(.impact, trigger: model.isPlaying)
    }

    /// Speed and sleep knobs either side of the output key. Each knob opens its choices; its
    /// pointer turns to the one in use.
    private var knobs: some View {
        HStack(alignment: .top) {
            Menu {
                Picker("Speed", selection: Binding { model.speed } set: { model.setSpeed($0) }) {
                    ForEach(ListeningSettings.speeds, id: \.self) { speed in
                        Text(AudiobookPlayerView.format(speed: speed)).tag(speed)
                    }
                }
            } label: {
                knob(degrees: speedDegrees, label: "Speed · \(speedName)")
            }
            .accessibilityLabel("Speed, \(speedName)")
            Spacer(minLength: 4)
            VStack(spacing: 8) {
                RoutePicker(activeTint: UIColor(Hifi.glow))
                    .frame(width: 70, height: 70)
                    .background(LinearGradient(colors: Hifi.key, startPoint: .top, endPoint: .bottom), in: .rect(cornerRadius: 6))
                    .shadow(color: .black.opacity(0.5), radius: 5, y: 4)
                HifiLabel("Output")
            }
            .frame(width: 96)
            Spacer(minLength: 4)
            Menu {
                SleepTimerChoices(model: model)
            } label: {
                knob(degrees: model.sleepTimer == nil ? -130 : 40, label: "Sleep · \(model.sleepLabel)")
            }
            .accessibilityLabel(model.sleepTimer == nil ? "Sleep timer" : "Sleep timer, \(model.sleepLabel)")
        }
        .padding(.top, 6)
        .sensoryFeedback(.selection, trigger: model.speed)
    }

    /// From -130° at the slowest speed to 130° at the fastest.
    private var speedDegrees: Double {
        let speeds = ListeningSettings.speeds
        guard let index = speeds.firstIndex(of: model.speed), speeds.count > 1 else { return 0 }
        return -130 + 260 * Double(index) / Double(speeds.count - 1)
    }

    private func knob(degrees: Double, label: String) -> some View {
        VStack(spacing: 8) {
            Knob(degrees: degrees)
            HifiLabel(label)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 110)
        .contentShape(.rect)
    }
}

/// The hi-fi deck's metal, glass and glow. The now-playing strip uses it too.
enum Hifi {
    static let panel = [Color(hex: 0x26272B), Color(hex: 0x131416)]
    static let well = Color(hex: 0x060607)
    static let bezel = Color(hex: 0x3A3B40)
    static let key = [Color(hex: 0x4A4C52), Color(hex: 0x2A2B2F)]
    static let keyDown = [Color(hex: 0x2A2B2F), Color(hex: 0x3A3C41)]
    static let faderCap = [Color(hex: 0x8D9097), Color(hex: 0xF1F2F4), Color(hex: 0x7B7E85)]
    static let knob = [Color(hex: 0xF4F5F7), Color(hex: 0x9A9DA4), Color(hex: 0x5D6067)]
    /// Lettering on keys.
    static let lettering = Color(hex: 0xECEEF2)
    /// Small print on the panel.
    static let print = Color(hex: 0xB9BCC2)
    static let display = [Color(hex: 0x04100F), Color(hex: 0x020807)]
    /// The display's vacuum-fluorescent glow.
    static let glow = Color(hex: 0x7FE9D6)
    static let amber = Color(hex: 0xFFB547)
    static let led = Color(hex: 0xFF5A3C)
    static let ledOff = Color(hex: 0x3A1512)
}

/// Fine vertical lines of brushed aluminium.
private struct BrushedMetal: View {
    var body: some View {
        Canvas { context, size in
            var lines = Path()
            for x in stride(from: 0, to: size.width, by: 3) {
                lines.addRect(CGRect(x: x, y: 0, width: 1, height: size.height))
            }
            context.fill(lines, with: .color(.white.opacity(0.022)))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Text lit on the display.
private struct Glowing: View {
    let text: String
    let font: Font

    init(_ text: String, font: Font) {
        self.text = text
        self.font = font
    }

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(Hifi.glow)
            .shadow(color: Hifi.glow.opacity(0.7), radius: 5)
    }
}

/// Small print naming a control.
private struct HifiLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(.caption2, weight: .semibold).width(.condensed))
            .tracking(1.5)
            .foregroundStyle(Hifi.print)
    }
}

/// A row of display segments, lit from the left.
private struct Segments: View {
    /// 0…1.
    let lit: Double
    var height: CGFloat = 9

    var body: some View {
        Canvas { context, size in
            let pitch: CGFloat = 9
            let width: CGFloat = 6
            let count = max(Int((size.width + pitch - width) / pitch), 1)
            let on = Int((Double(count) * min(max(lit, 0), 1)).rounded())
            for index in 0 ..< count {
                let rect = CGRect(x: CGFloat(index) * pitch, y: 0, width: width, height: size.height)
                context.fill(Path(rect), with: .color(index < on ? Hifi.glow : Hifi.glow.opacity(0.16)))
            }
        }
        .frame(height: height)
        .shadow(color: Hifi.glow.opacity(0.5), radius: 3)
        .accessibilityHidden(true)
    }
}

/// Left and right level meters that dance while the tape runs. They're decoration: the audio
/// isn't measured. Reduce Motion holds them still.
private struct LevelMeters: View {
    let isPlaying: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12, paused: !isPlaying || reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Grid(horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    Glowing("L", font: .system(.caption2, design: .monospaced))
                    Segments(lit: level(t, 7.3, 17.9, still: 0.6), height: 6)
                }
                GridRow {
                    Glowing("R", font: .system(.caption2, design: .monospaced))
                    Segments(lit: level(t + 0.7, 6.1, 15.3, still: 0.55), height: 6)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func level(_ t: Double, _ slow: Double, _ fast: Double, still: Double) -> Double {
        guard isPlaying else { return 0 }
        guard !reduceMotion else { return still }
        return min(max(0.55 + 0.25 * sin(t * slow) + 0.12 * sin(t * fast), 0.15), 0.95)
    }
}

/// A silver knob whose pointer turns to the setting in use.
private struct Knob: View {
    let degrees: Double

    var body: some View {
        Circle()
            .fill(RadialGradient(colors: Hifi.knob, center: UnitPoint(x: 0.4, y: 0.3), startRadius: 0, endRadius: 46))
            .overlay {
                Capsule()
                    .fill(Hifi.panel[1])
                    .frame(width: 4, height: 16)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 6)
                    .rotationEffect(.degrees(degrees))
            }
            .frame(width: 70, height: 70)
            .shadow(color: .black.opacity(0.6), radius: 5, y: 5)
            .animation(.snappy(duration: 0.25), value: degrees)
    }
}

/// A transport key's face: an LED that lights while the tape runs, the symbol, and its name.
private struct TransportLabel: View {
    let systemImage: String
    let text: String
    let isLit: Bool

    var body: some View {
        VStack(spacing: 6) {
            Capsule()
                .fill(isLit ? Hifi.led : Hifi.ledOff)
                .frame(width: 14, height: 4)
                .shadow(color: isLit ? Hifi.led : .clear, radius: 4)
            Image(systemName: systemImage).font(.title3)
            Text(text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 72)
    }
}

/// A soft rubber-topped key that sinks when pressed.
private struct SoftKeyStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed
        configuration.label
            .font(.system(.caption, weight: .bold).width(.condensed))
            .tracking(1.5)
            .textCase(.uppercase)
            .foregroundStyle(Hifi.lettering)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(LinearGradient(colors: down ? Hifi.keyDown : Hifi.key, startPoint: .top, endPoint: .bottom))
                    .overlay(alignment: .top) {
                        // Light catching the key's top edge.
                        Color.white.opacity(down ? 0.08 : 0.22).frame(height: 1).padding(.horizontal, 4)
                    }
                    .shadow(color: .black, radius: 0, y: down ? 0 : 2)
                    .shadow(color: .black.opacity(0.5), radius: down ? 2 : 6, y: down ? 1 : 4)
            }
            .offset(y: down ? 2 : 0)
            .opacity(isEnabled ? 1 : 0.4)
            .animation(.snappy(duration: 0.12), value: down)
    }
}
