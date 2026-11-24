import DogearCore
import SwiftUI

/// The pocket tape player skin: cream plastic, the Book loaded as a cassette behind a tinted
/// door, a mechanical counter and chunky piano keys.
struct PocketPlayer: View {
    let model: AudiobookPlayerModel
    let controls: PlayerControls

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(AppModel.self) private var app
    @State private var scrubbing: Double?
    /// How much the cassette shrinks to fit a narrow door.
    @State private var cassetteScale: CGFloat = 1
    /// The counter's wheels grow with the digits on them.
    @ScaledMetric(relativeTo: .title2) private var wheelWidth: CGFloat = 20
    @ScaledMetric(relativeTo: .title2) private var wheelHeight: CGFloat = 30
    @ScaledMetric(relativeTo: .title2) private var colonWidth: CGFloat = 8

    /// Under the whole player, filling the screen.
    static var background: some View {
        LinearGradient(colors: [Deck.bodyLight, Deck.bodyDark], startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
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
    private var duration: Double { model.bookSeconds }

    /// Close leaves the tape running under the library; Eject stops it. Chapters opens the
    /// cassette's insert.
    private var topBar: some View {
        HStack(spacing: 8) {
            Button("Close", systemImage: "chevron.down", action: controls.close)
                .labelStyle(.iconOnly)
                .buttonStyle(CapStyle())
                .accessibilityHint("Keeps playing")
            Button("Eject", systemImage: "eject.fill") { Task { await app.eject() } }
                .buttonStyle(CapStyle())
                .accessibilityHint("Stops playing and closes the player")
            Spacer()
            Text("DOGEAR")
                .font(.system(size: 16, weight: .bold).width(.condensed))
                .tracking(5)
                .foregroundStyle(Deck.print)
                .lineLimit(1)
                .fixedSize()
                .accessibilityHidden(true)
            Spacer()
            Button(model.contentsName, systemImage: model.contentsIcon, action: controls.showContents)
                .buttonStyle(CapStyle())
                .disabled(!model.hasContents)
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
            stripe: controls.stripe,
            throughBook: elapsed / duration, isPlaying: model.isPlaying, speed: Double(model.speed)
        )
        .scaleEffect(cassetteScale)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([model.title, model.author].compactMap { $0 }.joined(separator: ", "))
    }

    /// The Chapter or Track playing, on embossed label tape.
    private var chapterStrip: some View {
        Text((model.placeName ?? " ").uppercased())
            .font(.system(.subheadline, weight: .bold).width(.condensed))
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
                .font(Theme.label(.subheadline))
                .foregroundStyle(Theme.ink)
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(Color(hex: 0xFFE98A), in: .rect(cornerRadius: 2))
                .rotationEffect(.degrees(0.8))
        }
    }

    /// Whole-book time on a mechanical counter, with what's left of the tape beside it, or
    /// under it when large text leaves no room beside.
    private var counter: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom) {
                elapsedCounter
                Spacer()
                remainingCounter
            }
            VStack(alignment: .leading, spacing: 10) {
                elapsedCounter
                remainingCounter
            }
        }
    }

    private var elapsedCounter: some View {
        VStack(alignment: .leading, spacing: 4) {
            DeckLabel("Tape counter")
            HStack(spacing: 2) {
                ForEach(Array(AudiobookPlayerView.wheels(elapsed).enumerated()), id: \.offset) { _, character in
                    Text(String(character))
                        .font(.system(.title2, design: .monospaced, weight: .medium))
                        .foregroundStyle(Color(hex: 0xF4F1E8))
                        .frame(width: character == ":" ? colonWidth : wheelWidth, height: wheelHeight)
                        .background(character == ":" ? Color.clear : Color(hex: 0x161616), in: .rect(cornerRadius: 2))
                }
            }
            .padding(4)
            .background(.black, in: .rect(cornerRadius: 4))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Elapsed \(AudiobookPlayerView.format(elapsed))")
    }

    private var remainingCounter: some View {
        VStack(alignment: .trailing, spacing: 4) {
            DeckLabel("Tape left")
            Text("-" + AudiobookPlayerView.wheels(max(0, duration - elapsed)))
                .font(.system(.title2, design: .monospaced, weight: .medium))
                .foregroundStyle(Deck.print)
                .frame(minHeight: wheelHeight + 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Remaining \(AudiobookPlayerView.format(max(0, duration - elapsed)))")
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
        .accessibilityValue(AudiobookPlayerView.format(elapsed))
    }

    private var transport: some View {
        HStack(spacing: 8) {
            Button {
                model.skip(by: .zero - model.skipBack)
            } label: {
                KeyLabel(systemImage: "backward.fill", text: "\(Int(model.skipBack.seconds)) SEC")
            }
            .buttonStyle(KeyStyle())
            .accessibilityLabel("Back \(Int(model.skipBack.seconds)) seconds")
            Button {
                model.togglePlayback()
            } label: {
                KeyLabel(systemImage: model.isPlaying ? "pause.fill" : "play.fill", text: model.isPlaying ? "PAUSE" : "PLAY")
            }
            // A tape player's play key stays down while the tape runs.
            .buttonStyle(KeyStyle(isMain: true, isDown: model.isPlaying))
            .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
            Button {
                model.skip(by: model.skipForward)
            } label: {
                KeyLabel(systemImage: "forward.fill", text: "\(Int(model.skipForward.seconds)) SEC")
            }
            .buttonStyle(KeyStyle())
            .accessibilityLabel("Forward \(Int(model.skipForward.seconds)) seconds")
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
                DeckLabel(AudiobookPlayerView.format(speed: model.speed))
            }
            HStack(spacing: 0) {
                ForEach(ListeningSettings.speeds, id: \.self) { speed in
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
                                .font(.system(.caption2, weight: .bold).width(.condensed))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .foregroundStyle(Deck.print)
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Speed \(AudiobookPlayerView.format(speed: speed))")
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
            SleepTimerChoices(model: model)
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .trailing, spacing: 2) {
                    DeckLabel("Sleep timer")
                    Text(model.sleepLabel)
                        .font(.system(.subheadline, weight: .bold).width(.condensed))
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
        .accessibilityLabel(model.sleepTimer == nil ? "Sleep timer" : "Sleep timer, \(model.sleepLabel)")
    }
}

/// The pocket player's plastic, print and keys. The now-playing strip uses it too.
enum Deck {
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
            .font(.system(.caption2, weight: .bold).width(.condensed))
            .tracking(1.5)
            .foregroundStyle(Deck.print.opacity(0.85))
    }
}

/// A small dark button on the top edge.
private struct CapStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.caption, weight: .bold).width(.condensed))
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
            Image(systemName: systemImage).font(.title2)
            Text(text).font(.system(.caption2, weight: .bold).width(.condensed)).tracking(1.5)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
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
