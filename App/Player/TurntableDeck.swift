import DogearCore
import SwiftUI

/// The turntable skin: a walnut record deck with the Book as an LP. The record turns while it
/// plays, the tonearm creeps from the rim to the label as the listener gets through the Book,
/// and the played grooves are a shade lighter.
struct TurntableDeck: View {
    let model: AudiobookPlayerModel
    let controls: PlayerControls

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(AppModel.self) private var app
    @State private var scrubbing: Double?
    /// How much the deck's plinth shrinks to fit a narrow screen.
    @State private var plinthScale: CGFloat = 1

    /// Under the whole deck, filling the screen.
    static var background: some View {
        LinearGradient(colors: Walnut.wood, startPoint: .top, endPoint: .bottom)
            .overlay { WoodGrain() }
    }

    var body: some View {
        switch model.state {
        case .opening:
            VStack(spacing: 14) {
                topBar
                plinth { ProgressView("Opening…").tint(Walnut.brass).foregroundStyle(Theme.paper) }
            }
        case let .failed(message):
            VStack(spacing: 14) {
                topBar
                plinth { EmptyView() }
                ContentUnavailableView("Can't play this audiobook", systemImage: "exclamationmark.triangle", description: Text(message))
                    .foregroundStyle(Theme.paper)
            }
        case .ready:
            if sizeClass == .regular {
                // Record beside the controls, using the iPad's width.
                VStack(spacing: 14) {
                    topBar
                    HStack(alignment: .top, spacing: 32) {
                        VStack(spacing: 14) {
                            plinth { record }
                            problemNote
                        }
                        .frame(maxWidth: 440)
                        VStack(spacing: 14) {
                            nowPlayingCard
                            scrubber
                            transport
                            footer
                        }
                        .frame(maxWidth: 440)
                    }
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 14) {
                    topBar
                    plinth { record }
                    problemNote
                    nowPlayingCard
                    scrubber
                    transport
                    footer
                }
            }
        }
    }

    private var elapsed: Double { scrubbing ?? model.currentTime.seconds }
    private var duration: Double { model.bookSeconds }

    /// Close leaves the record playing under the library; Lift (Eject) stops it.
    private var topBar: some View {
        HStack(spacing: 8) {
            Button("Close", systemImage: "chevron.down", action: controls.close)
                .labelStyle(.iconOnly)
                .buttonStyle(EnamelKeyStyle())
                .accessibilityHint("Keeps playing")
            Button { Task { await app.eject() } } label: {
                Label("Lift", systemImage: "eject.fill")
            }
            .buttonStyle(EnamelKeyStyle())
            .accessibilityLabel("Eject")
            .accessibilityHint("Stops playing and closes the player")
            Spacer()
            Text("DOGEAR")
                .font(.system(size: 16, weight: .heavy).width(.condensed))
                .tracking(5)
                .foregroundStyle(Theme.paper)
                .shadow(color: .black.opacity(0.4), radius: 0, y: 1)
                .lineLimit(1)
                .fixedSize()
                .accessibilityHidden(true)
            Spacer()
            Button(model.contentsName, systemImage: model.contentsIcon, action: controls.showContents)
                .buttonStyle(EnamelKeyStyle())
                .disabled(!model.hasContents)
        }
    }

    /// The deck's dark plinth the record sits on, scaled down to fit a narrow screen.
    private func plinth(@ViewBuilder _ loaded: () -> some View) -> some View {
        LinearGradient(colors: Walnut.plinth, startPoint: .top, endPoint: .bottom)
            .frame(height: LoadedRecord.size.height * plinthScale + 20)
            .overlay { loaded().scaleEffect(plinthScale) }
            .clipShape(.rect(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(Walnut.plinthEdge, lineWidth: 2) }
            .shadow(color: .black.opacity(0.5), radius: 9, y: 6)
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { width in
                plinthScale = min(1, (width - 16) / LoadedRecord.size.width)
            }
    }

    private var record: some View {
        LoadedRecord(
            title: model.title, author: model.author,
            label: controls.stripe,
            throughBook: elapsed / duration, isPlaying: model.isPlaying, speed: Double(model.speed)
        )
        .overlay(alignment: .bottomLeading) { speedSwitch.padding(14) }
        .accessibilityElement(children: .contain)
    }

    /// The speed selector in the plinth's corner; it opens every speed.
    private var speedSwitch: some View {
        Menu {
            Picker("Speed", selection: Binding { model.speed } set: { model.setSpeed($0) }) {
                ForEach(ListeningSettings.speeds, id: \.self) { speed in
                    Text(AudiobookPlayerView.format(speed: speed)).tag(speed)
                }
            }
        } label: {
            VStack(spacing: 3) {
                Text(AudiobookPlayerView.format(speed: model.speed))
                    .font(.system(.footnote, weight: .bold).width(.condensed))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 9)
                    .frame(minWidth: 44, minHeight: 30)
                    .background(LinearGradient(colors: Theme.brass, startPoint: .top, endPoint: .bottom), in: .rect(cornerRadius: 5))
                Text("SPEED")
                    .font(.system(size: 9, weight: .bold).width(.condensed))
                    .tracking(1.5)
                    .foregroundStyle(Walnut.print)
            }
            .contentShape(.rect)
        }
        .accessibilityLabel("Speed, \(AudiobookPlayerView.format(speed: model.speed))")
        .sensoryFeedback(.selection, trigger: model.speed)
    }

    /// The sleeve's paper card naming the Chapter or Track playing, with the time.
    private var nowPlayingCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("NOW PLAYING")
                .font(.system(.caption2, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(Theme.ribbonDark)
                .accessibilityHidden(true)
            Text(model.placeName ?? model.title)
                .font(.system(.headline, design: .serif))
                .foregroundStyle(Theme.pen)
                .lineLimit(2)
            HStack {
                Text(AudiobookPlayerView.wheels(elapsed))
                    .accessibilityLabel("Elapsed \(AudiobookPlayerView.format(elapsed))")
                Spacer()
                Text("-" + AudiobookPlayerView.wheels(max(0, duration - elapsed)))
                    .accessibilityLabel("Remaining \(AudiobookPlayerView.format(max(0, duration - elapsed)))")
            }
            .font(.system(.subheadline).monospacedDigit())
            .foregroundStyle(Theme.inkSoft)
            .padding(.top, 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.paper, in: .rect(cornerRadius: 4))
        .shadow(color: .black.opacity(0.45), radius: 5, y: 3)
        .environment(\.colorScheme, .light)
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
        .tint(Walnut.brass)
        .accessibilityLabel("Position")
        .accessibilityValue(AudiobookPlayerView.format(elapsed))
    }

    private var transport: some View {
        HStack(spacing: 10) {
            Button {
                model.skip(by: .zero - model.skipBack)
            } label: {
                transportLabel("backward.fill", "\(Int(model.skipBack.seconds)) sec")
            }
            .buttonStyle(EnamelKeyStyle(isTall: true))
            .accessibilityLabel("Back \(Int(model.skipBack.seconds)) seconds")
            Button {
                model.togglePlayback()
            } label: {
                transportLabel(model.isPlaying ? "pause.fill" : "play.fill", model.isPlaying ? "Pause" : "Play")
            }
            // Brass, and it stays down while the record turns.
            .buttonStyle(EnamelKeyStyle(isTall: true, isBrass: true, isDown: model.isPlaying))
            .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
            Button {
                model.skip(by: model.skipForward)
            } label: {
                transportLabel("forward.fill", "\(Int(model.skipForward.seconds)) sec")
            }
            .buttonStyle(EnamelKeyStyle(isTall: true))
            .accessibilityLabel("Forward \(Int(model.skipForward.seconds)) seconds")
        }
        .sensoryFeedback(.impact, trigger: model.isPlaying)
    }

    private func transportLabel(_ systemImage: String, _ text: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage).font(.title2)
            Text(text).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    /// The sleep knob and the output picker along the plinth's front.
    private var footer: some View {
        HStack {
            Menu {
                SleepTimerChoices(model: model)
            } label: {
                HStack(spacing: 10) {
                    Circle()
                        .fill(RadialGradient(colors: Walnut.knob, center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: 34))
                        .overlay {
                            Capsule()
                                .fill(Theme.paper)
                                .frame(width: 3, height: 13)
                                .frame(maxHeight: .infinity, alignment: .top)
                                .padding(.top, 5)
                                .rotationEffect(.degrees(model.sleepTimer == nil ? -120 : 40))
                        }
                        .frame(width: 52, height: 52)
                        .shadow(color: .black.opacity(0.5), radius: 4, y: 4)
                        .animation(.snappy(duration: 0.25), value: model.sleepTimer == nil)
                    VStack(alignment: .leading, spacing: 2) {
                        WalnutLabel("Sleep timer")
                        Text(model.sleepLabel)
                            .font(.system(.subheadline, weight: .bold).width(.condensed))
                            .monospacedDigit()
                            .foregroundStyle(Theme.paper)
                    }
                }
                .contentShape(.rect)
            }
            .accessibilityLabel(model.sleepTimer == nil ? "Sleep timer" : "Sleep timer, \(model.sleepLabel)")
            Spacer()
            HStack(spacing: 8) {
                WalnutLabel("Output")
                RoutePicker(activeTint: UIColor(Walnut.brass))
                    .frame(width: 44, height: 44)
                    .background(Walnut.plinth[1], in: .circle)
            }
        }
    }
}

/// The turntable's wood, plinth, brass and enamel.
enum Walnut {
    static let wood = [Color(hex: 0x8A5A36), Color(hex: 0x5E3A22)]
    static let plinth = [Color(hex: 0x2A2724), Color(hex: 0x161412)]
    static let plinthEdge = Color(hex: 0x3C3833)
    static let brass = Color(hex: 0xE8C77A)
    static let enamel = [Color(hex: 0xEFE9D8), Color(hex: 0xCFC7B3)]
    static let enamelDown = [Color(hex: 0xD9D1BC), Color(hex: 0xE6DFCC)]
    static let enamelEdge = Color(hex: 0x6B5A44)
    static let brassFace = [Color(hex: 0xE8C77A), Color(hex: 0xB98F3C)]
    static let brassEdge = Color(hex: 0x6B4F1C)
    static let knob = [Color(hex: 0xC9A57A), Color(hex: 0x6B4126)]
    /// Small print on the plinth and the wood.
    static let print = Color(hex: 0xD8CBB4)
    static let vinyl = [Color(hex: 0x121212), Color(hex: 0x1D1D1D)]
    static let platter = [Color(hex: 0xB9BCC2), Color(hex: 0x8D9097)]
}

/// Faint grain running down the walnut.
private struct WoodGrain: View {
    var body: some View {
        Canvas { context, size in
            var grain = Path()
            for x in stride(from: 0, to: size.width, by: 7) {
                grain.addRect(CGRect(x: x, y: 0, width: 2, height: size.height))
            }
            context.fill(grain, with: .color(.black.opacity(0.05)))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Small print naming a control.
private struct WalnutLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(.caption2, weight: .bold).width(.condensed))
            .tracking(1.5)
            .foregroundStyle(Walnut.print)
    }
}

/// An enamel key; the main one is brass and can stay down.
private struct EnamelKeyStyle: ButtonStyle {
    var isTall = false
    var isBrass = false
    var isDown = false

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let down = isDown || configuration.isPressed
        let face = isBrass ? Walnut.brassFace : (down ? Walnut.enamelDown : Walnut.enamel)
        let edge = isBrass ? Walnut.brassEdge : Walnut.enamelEdge
        configuration.label
            .font(.system(.caption, weight: .heavy).width(.condensed))
            .tracking(1.5)
            .textCase(.uppercase)
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 12)
            .frame(minHeight: isTall ? 72 : 44)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(colors: face, startPoint: .top, endPoint: .bottom))
                    // The key's front edge, which disappears as it goes down.
                    .shadow(color: edge, radius: 0, y: down ? 1 : 5)
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 6)
            }
            .offset(y: down ? 4 : 0)
            .opacity(isEnabled ? 1 : 0.4)
            .animation(.snappy(duration: 0.12), value: down)
    }
}

/// The record on its platter with the tonearm over it. The arm sits on the groove for how far
/// through the Book the listener is; the record turns while it plays.
struct LoadedRecord: View {
    static let size = CGSize(width: 330, height: 310)
    /// Where the platter turns and the arm pivots, in the drawing's own points.
    private static let centre = CGPoint(x: 150, y: 160)
    private static let pivot = CGPoint(x: 320, y: 36)
    private static let armLength: CGFloat = 238
    /// The arm's swing from the outermost groove to the innermost, measured for the points above.
    private static let armAtRim = 22.5
    private static let armAtLabel = 41.5
    private static let grooves: (outer: CGFloat, inner: CGFloat) = (124, 54)

    let title: String
    let author: String?
    let label: Color
    /// 0…1.
    let throughBook: Double
    let isPlaying: Bool
    let speed: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let through = min(max(throughBook, 0), 1)
        let groove = Self.grooves.outer - CGFloat(through) * (Self.grooves.outer - Self.grooves.inner)
        ZStack(alignment: .topLeading) {
            TimelineView(.animation(paused: !isPlaying || reduceMotion)) { timeline in
                // 33⅓ turns a minute at 1×, faster with the speed.
                let angle = Angle.degrees(timeline.date.timeIntervalSinceReferenceDate * 200 * speed)
                disc(groove: groove)
                    .rotationEffect(angle)
            }
            .frame(width: 260, height: 260)
            .offset(x: Self.centre.x - 130, y: Self.centre.y - 130)
            tonearm(degrees: Self.armAtRim + through * (Self.armAtLabel - Self.armAtRim))
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([title, author].compactMap { $0 }.joined(separator: ", "))
    }

    private func disc(groove: CGFloat) -> some View {
        ZStack {
            Circle().fill(AngularGradient(colors: Walnut.platter + Walnut.platter + [Walnut.platter[0]], center: .center))
            Circle()
                .fill(RadialGradient(colors: Walnut.vinyl, center: .center, startRadius: 0, endRadius: 124))
                .padding(6)
            // Grooves.
            ForEach(Array(stride(from: 60, through: 120, by: 6)), id: \.self) { radius in
                Circle()
                    .stroke(.white.opacity(0.045), lineWidth: 1)
                    .frame(width: CGFloat(radius) * 2, height: CGFloat(radius) * 2)
            }
            // The played part of the side, from the rim in to the arm.
            Circle()
                .stroke(Walnut.brass.opacity(0.14), lineWidth: Self.grooves.outer - groove)
                .frame(width: Self.grooves.outer + groove, height: Self.grooves.outer + groove)
            // Light catching the vinyl.
            Circle()
                .fill(AngularGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .white.opacity(0.12), location: 0.1),
                        .init(color: .clear, location: 0.16),
                        .init(color: .clear, location: 0.58),
                        .init(color: .white.opacity(0.08), location: 0.62),
                        .init(color: .clear, location: 0.66),
                    ],
                    center: .center
                ))
                .padding(6)
            Circle()
                .fill(label)
                .frame(width: 100, height: 100)
                .overlay {
                    VStack(spacing: 2) {
                        Text(title)
                            .font(.system(size: 10.5, weight: .bold, design: .serif))
                            .lineLimit(2)
                        if let author {
                            Text(author)
                                .font(.system(size: 9))
                                .lineLimit(1)
                        }
                    }
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.paper)
                    .shadow(color: .black.opacity(0.5), radius: 1)
                    .padding(14)
                }
            Circle().fill(Color(hex: 0xDDDDDD)).frame(width: 7, height: 7)
        }
    }

    /// The arm hangs down from its pivot and swings in towards the label.
    private func tonearm(degrees: Double) -> some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                Capsule()
                    .fill(LinearGradient(colors: [Color(hex: 0x9A9DA4), Color(hex: 0xF1F2F4), Color(hex: 0x7B7E85)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: 7, height: Self.armLength - 20)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(hex: 0x222222))
                    .overlay { RoundedRectangle(cornerRadius: 3).strokeBorder(Color(hex: 0x555555), lineWidth: 1) }
                    .frame(width: 18, height: 26)
            }
            .frame(width: 18)
            .shadow(color: .black.opacity(0.5), radius: 3, x: 3, y: 3)
            .rotationEffect(.degrees(degrees), anchor: .top)
            .offset(x: Self.pivot.x - 9, y: Self.pivot.y)
            .animation(.easeInOut(duration: 0.4), value: degrees)
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0xEEEEEE), Color(hex: 0x888888), Color(hex: 0x444444)], center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: 26))
                .frame(width: 44, height: 44)
                .offset(x: Self.pivot.x - 22, y: Self.pivot.y - 22)
        }
    }
}
