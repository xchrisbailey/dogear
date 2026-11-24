import DogearCore
import SwiftUI

/// The valve radio skin: a 1950s tabletop wireless in oxblood bakelite with a brass grille. The
/// lit dial is the Book: Chapters (or Tracks) are stations along the band and the red pointer
/// is how far through the listener is. Dragging along the dial tunes, which scrubs. The magic
/// eye glows while it plays.
struct ValveRadio: View {
    let model: AudiobookPlayerModel
    let controls: PlayerControls

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(AppModel.self) private var app
    @State private var scrubbing: Double?

    /// Under the whole set, filling the screen.
    static var background: some View {
        LinearGradient(colors: Bakelite.body, startPoint: .top, endPoint: .bottom)
            .overlay {
                RadialGradient(colors: [.white.opacity(0.12), .clear], center: UnitPoint(x: 0.5, y: 0.15), startRadius: 0, endRadius: 420)
            }
    }

    var body: some View {
        switch model.state {
        case .opening:
            VStack(spacing: 14) {
                topBar
                grille
                ProgressView("Warming up…").tint(Bakelite.dialLight).foregroundStyle(Bakelite.cream)
            }
        case let .failed(message):
            VStack(spacing: 14) {
                topBar
                grille
                ContentUnavailableView("Can't play this audiobook", systemImage: "exclamationmark.triangle", description: Text(message))
                    .foregroundStyle(Bakelite.cream)
            }
        case .ready:
            if sizeClass == .regular {
                // Grille and dial beside the controls, using the iPad's width.
                VStack(spacing: 14) {
                    topBar
                    HStack(alignment: .top, spacing: 32) {
                        VStack(spacing: 14) {
                            grille
                            dial
                            times
                            problemNote
                        }
                        .frame(maxWidth: 440)
                        VStack(spacing: 14) {
                            presets
                            knobs
                        }
                        .frame(maxWidth: 440)
                    }
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 14) {
                    topBar
                    grille
                    dial
                    times
                    problemNote
                    presets
                    knobs
                }
            }
        }
    }

    private var elapsed: Double { scrubbing ?? model.currentTime.seconds }
    private var duration: Double { model.bookSeconds }

    /// Close leaves the set playing under the library; Off (Eject) stops it.
    private var topBar: some View {
        HStack(spacing: 8) {
            Button("Close", systemImage: "chevron.down", action: controls.close)
                .labelStyle(.iconOnly)
                .buttonStyle(IvoryKeyStyle(isRound: true))
                .accessibilityHint("Keeps playing")
            Button { Task { await app.eject() } } label: {
                Label("Off", systemImage: "power")
            }
            .buttonStyle(IvoryKeyStyle(isRound: true))
            .accessibilityLabel("Eject")
            .accessibilityHint("Stops playing and closes the player")
            Spacer()
            Text("DOGEAR")
                .font(.system(size: 16, weight: .heavy, design: .serif))
                .tracking(5)
                .foregroundStyle(Bakelite.cream)
                .lineLimit(1)
                .fixedSize()
                .accessibilityHidden(true)
            Spacer()
            Button(model.info?.isFolder == true ? "Tracks" : "Stations", systemImage: model.contentsIcon, action: controls.showContents)
                .buttonStyle(IvoryKeyStyle(isRound: true))
                .disabled(!model.hasContents)
                .accessibilityLabel(model.contentsName)
        }
    }

    /// The brass speaker grille with the magic eye in it.
    private var grille: some View {
        Canvas { context, size in
            var bars = Path()
            for x in stride(from: 8, to: size.width - 8, by: 10) {
                bars.addRect(CGRect(x: x, y: 0, width: 3, height: size.height))
            }
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Bakelite.cloth))
            context.fill(bars, with: .color(Bakelite.brass))
        }
        .frame(height: 150)
        .overlay(alignment: .bottom) {
            MagicEye(isPlaying: model.isPlaying)
                .padding(.bottom, 16)
        }
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 70, bottomLeadingRadius: 10, bottomTrailingRadius: 10, topTrailingRadius: 70))
        .overlay {
            UnevenRoundedRectangle(topLeadingRadius: 70, bottomLeadingRadius: 10, bottomTrailingRadius: 10, topTrailingRadius: 70)
                .strokeBorder(Bakelite.dialLight, lineWidth: 4)
        }
        .shadow(color: .black.opacity(0.4), radius: 6, y: 5)
        .accessibilityHidden(true)
    }

    /// The lit dial. Chapters are stations along the band; the pointer is the Position.
    private var dial: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(bandName)
                .font(.system(size: 10, weight: .bold, design: .serif))
                .tracking(2)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .accessibilityHidden(true)
            GeometryReader { proxy in
                let band = max(proxy.size.width - 28, 1)
                ZStack(alignment: .topLeading) {
                    Ticks()
                        .frame(height: 9)
                        .padding(.horizontal, 14)
                        .padding(.top, 8)
                    ForEach(stations(across: band), id: \.position) { station in
                        Text(station.name)
                            .font(.system(size: 10, weight: .bold, design: .serif))
                            .fixedSize()
                            .position(x: 14 + station.position * band, y: 30)
                    }
                    // The pointer.
                    Capsule()
                        .fill(Theme.ribbon)
                        .frame(width: 3)
                        .shadow(color: Theme.ribbon.opacity(0.6), radius: 4)
                        .padding(.vertical, 2)
                        .offset(x: 14 + CGFloat(elapsed / duration) * band - 1.5)
                        .animation(.easeOut(duration: 0.3), value: scrubbing == nil ? elapsed : 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .contentShape(.rect)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            scrubbing = min(max(Double((value.location.x - 14) / band), 0), 1) * duration
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
            Text(model.placeName ?? model.title)
                .font(.system(.headline, design: .serif).italic())
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
        }
        .foregroundStyle(Bakelite.dialInk)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            LinearGradient(colors: [Bakelite.dialLight, Bakelite.dial], startPoint: .top, endPoint: .bottom)
                .overlay { RadialGradient(colors: [Bakelite.lamp.opacity(model.isPlaying ? 0.45 : 0.15), .clear], center: .center, startRadius: 0, endRadius: 220) }
                .animation(.easeInOut(duration: 0.6), value: model.isPlaying)
        }
        .clipShape(.rect(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Bakelite.brass, lineWidth: 3) }
        .shadow(color: Bakelite.lamp.opacity(model.isPlaying ? 0.3 : 0), radius: 14)
        .environment(\.colorScheme, .light)
    }

    private var bandName: String {
        model.info?.isFolder == true ? "TRACKS" : "CHAPTERS"
    }

    /// Stations along the band, named by number. Where they'd crowd, only some are named.
    private func stations(across band: CGFloat) -> [Station] {
        let starts: [Duration] = if model.info?.isFolder == true {
            model.info?.tracks.map(\.start) ?? []
        } else {
            model.info?.chapters.map(\.start) ?? []
        }
        var named: [Station] = []
        var lastX = -CGFloat.infinity
        for (index, start) in starts.enumerated() {
            let position = min(max(start.seconds / duration, 0), 1)
            let x = CGFloat(position) * band
            guard x - lastX >= 30 else { continue }
            named.append(Station(position: position, name: "\(index + 1)"))
            lastX = x
        }
        return named
    }

    private var times: some View {
        HStack {
            Text(AudiobookPlayerView.wheels(elapsed))
                .accessibilityLabel("Elapsed \(AudiobookPlayerView.format(elapsed))")
            Spacer()
            Text("-" + AudiobookPlayerView.wheels(max(0, duration - elapsed)))
                .opacity(0.85)
                .accessibilityLabel("Remaining \(AudiobookPlayerView.format(max(0, duration - elapsed)))")
        }
        .font(.system(.subheadline, design: .serif, weight: .semibold).monospacedDigit())
        .foregroundStyle(Bakelite.cream)
    }

    @ViewBuilder private var problemNote: some View {
        if let problem = model.problem {
            Label(problem, systemImage: "exclamationmark.triangle")
                .font(Theme.label(.subheadline))
                .foregroundStyle(Theme.ink)
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(Color(hex: 0xFFE98A), in: .rect(cornerRadius: 2))
                .rotationEffect(.degrees(0.8))
        }
    }

    /// The row of ivory push-buttons. Play stays down while the set plays.
    private var presets: some View {
        HStack(spacing: 8) {
            Button {
                model.skip(by: .zero - model.skipBack)
            } label: {
                presetLabel("backward.fill", "\(Int(model.skipBack.seconds)) sec")
            }
            .buttonStyle(IvoryKeyStyle(isTall: true))
            .accessibilityLabel("Back \(Int(model.skipBack.seconds)) seconds")
            Button {
                model.togglePlayback()
            } label: {
                presetLabel(model.isPlaying ? "pause.fill" : "play.fill", model.isPlaying ? "Pause" : "Play")
            }
            .buttonStyle(IvoryKeyStyle(isTall: true, isDown: model.isPlaying))
            .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
            Button {
                model.skip(by: model.skipForward)
            } label: {
                presetLabel("forward.fill", "\(Int(model.skipForward.seconds)) sec")
            }
            .buttonStyle(IvoryKeyStyle(isTall: true))
            .accessibilityLabel("Forward \(Int(model.skipForward.seconds)) seconds")
        }
        .sensoryFeedback(.impact, trigger: model.isPlaying)
    }

    private func presetLabel(_ systemImage: String, _ text: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage).font(.title3)
            Text(text).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    /// Speed and sleep knobs either side of the output socket.
    private var knobs: some View {
        HStack(alignment: .top) {
            Menu {
                Picker("Speed", selection: Binding { model.speed } set: { model.setSpeed($0) }) {
                    ForEach(ListeningSettings.speeds, id: \.self) { speed in
                        Text(AudiobookPlayerView.format(speed: speed)).tag(speed)
                    }
                }
            } label: {
                knob(degrees: speedDegrees, label: "Speed · \(AudiobookPlayerView.format(speed: model.speed))")
            }
            .accessibilityLabel("Speed, \(AudiobookPlayerView.format(speed: model.speed))")
            Spacer(minLength: 4)
            VStack(spacing: 8) {
                RoutePicker(activeTint: UIColor(Bakelite.dialLight))
                    .frame(width: 64, height: 64)
                    .background(RadialGradient(colors: Bakelite.knob, center: UnitPoint(x: 0.4, y: 0.3), startRadius: 0, endRadius: 44), in: .circle)
                    .shadow(color: .black.opacity(0.5), radius: 5, y: 5)
                RadioLabel("Output")
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
        .padding(.top, 4)
        .sensoryFeedback(.selection, trigger: model.speed)
    }

    private var speedDegrees: Double {
        let speeds = ListeningSettings.speeds
        guard let index = speeds.firstIndex(of: model.speed), speeds.count > 1 else { return 0 }
        return -130 + 260 * Double(index) / Double(speeds.count - 1)
    }

    private func knob(degrees: Double, label: String) -> some View {
        VStack(spacing: 8) {
            Circle()
                .fill(RadialGradient(colors: Bakelite.knob, center: UnitPoint(x: 0.4, y: 0.3), startRadius: 0, endRadius: 44))
                .overlay {
                    Capsule()
                        .fill(Bakelite.dialLight)
                        .frame(width: 4, height: 15)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.top, 6)
                        .rotationEffect(.degrees(degrees))
                }
                .frame(width: 64, height: 64)
                .shadow(color: .black.opacity(0.5), radius: 5, y: 5)
                .animation(.snappy(duration: 0.25), value: degrees)
            RadioLabel(label)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 110)
        .contentShape(.rect)
    }
}

/// A named mark on the dial: a Chapter or Track's start, from 0 to 1 along the band.
private struct Station {
    let position: Double
    let name: String
}

/// The radio's bakelite, brass, cloth and dial.
enum Bakelite {
    static let body = [Color(hex: 0x7A1F24), Color(hex: 0x4A1014)]
    static let cream = Color(hex: 0xF4EAD2)
    static let brass = Color(hex: 0xC9A04F)
    /// The speaker cloth behind the grille.
    static let cloth = Color(hex: 0x3A2610)
    static let dial = Color(hex: 0xE3C983)
    static let dialLight = Color(hex: 0xF6E7B8)
    static let dialInk = Color(hex: 0x3A2610)
    /// The dial lamp's warm light.
    static let lamp = Color(hex: 0xFFAA3C)
    static let ivory = [Color(hex: 0xF2E6C9), Color(hex: 0xD4C296)]
    static let ivoryDown = [Color(hex: 0xD4C296), Color(hex: 0xE8D8AE)]
    static let ivoryEdge = Color(hex: 0x6B4F1C)
    static let knob = [Color(hex: 0x5A3A22), Color(hex: 0x24140B)]
    static let eye = Color(hex: 0x3EE08A)
    static let eyeDark = Color(hex: 0x0A1A10)
}

/// The dial's fine scale.
private struct Ticks: View {
    var body: some View {
        Canvas { context, size in
            var ticks = Path()
            for x in stride(from: 0, through: size.width, by: 6) {
                ticks.addRect(CGRect(x: x, y: 0, width: 1, height: size.height))
            }
            context.fill(ticks, with: .color(Bakelite.dialInk.opacity(0.8)))
        }
        .accessibilityHidden(true)
    }
}

/// The tuning indicator valve: a green ring that glows and flickers while the set plays. Reduce
/// Motion holds it steady.
private struct MagicEye: View {
    let isPlaying: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: !isPlaying || reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let glow = isPlaying ? (reduceMotion ? 0.85 : 0.75 + 0.2 * sin(t * 9) * sin(t * 2.3)) : 0.25
            Circle()
                .fill(Bakelite.eyeDark)
                .overlay {
                    Circle()
                        .strokeBorder(Bakelite.eye.opacity(glow), lineWidth: 10)
                        .padding(4)
                }
                .overlay { Circle().fill(Bakelite.eyeDark).padding(16) }
                .shadow(color: Bakelite.eye.opacity(glow * 0.8), radius: 10)
        }
        .frame(width: 48, height: 48)
        .overlay { Circle().strokeBorder(Bakelite.brass, lineWidth: 4) }
        .animation(.easeInOut(duration: 0.6), value: isPlaying)
    }
}

/// Small print naming a control.
private struct RadioLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(.caption2, weight: .bold))
            .tracking(1.5)
            .foregroundStyle(Bakelite.cream.opacity(0.9))
    }
}

/// An ivory push-button that sinks when pressed and can stay down.
private struct IvoryKeyStyle: ButtonStyle {
    var isTall = false
    var isRound = false
    var isDown = false

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let down = isDown || configuration.isPressed
        configuration.label
            .font(.system(.caption, weight: .heavy))
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 12)
            .frame(minHeight: isTall ? 64 : 44)
            .background {
                RoundedRectangle(cornerRadius: isRound ? 22 : 6)
                    .fill(LinearGradient(colors: down ? Bakelite.ivoryDown : Bakelite.ivory, startPoint: .top, endPoint: .bottom))
                    .shadow(color: Bakelite.ivoryEdge, radius: 0, y: down ? 1 : 4)
                    .shadow(color: .black.opacity(0.35), radius: 5, y: 5)
            }
            .offset(y: down ? 3 : 0)
            .opacity(isEnabled ? 1 : 0.4)
            .animation(.snappy(duration: 0.12), value: down)
    }
}
