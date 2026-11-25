import DogearCore
import SwiftUI

/// The Pocket Player: the Book's title, a portable tape player with the Book loaded as a
/// cassette, and under it the one set of controls. The player is an illustration only, so
/// nothing that looks pressable on it is there to press.
struct PocketPlayer: View {
    let model: AudiobookPlayerModel
    /// Closes the player and leaves the tape running.
    let close: () -> Void
    /// Opens the Chapters, or the Tracks of a folder audiobook.
    let showContents: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Where a drag on the scrubber has got to, shown until it's let go.
    @State private var scrubbing: Double?

    var body: some View {
        GeometryReader { proxy in
            // Side by side in a short, wide window, with the title and artwork together.
            let twoColumns = proxy.size.width >= 560 && proxy.size.height < proxy.size.width
            let art = min(twoColumns ? 400 : proxy.size.width >= 560 ? 400 : 360, proxy.size.width - 32, max(proxy.size.height * 0.34, 160) * PocketDrawing.ratio)
            ScrollView {
                VStack(spacing: 0) {
                    topBar
                    if twoColumns {
                        HStack(alignment: .center, spacing: 32) {
                            VStack(spacing: 16) {
                                metadata
                                pocket(width: min(art, (proxy.size.width - 64) / 2))
                            }
                            .frame(maxWidth: .infinity)
                            functional
                                .frame(maxWidth: .infinity)
                        }
                        .padding(.top, 12)
                    } else {
                        metadata
                            .padding(.top, 12)
                        pocket(width: art)
                            .padding(.top, 16)
                        functional
                            .padding(.top, 16)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .frame(maxWidth: twoColumns ? 1040 : 560)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .top)
            }
            // Pulled down past the top, the player closes like a sheet, and the tape plays on.
            .modifier(PullsDownToClose(close: close))
        }
    }

    private var elapsed: Double { scrubbing ?? model.currentTime.seconds }

    /// Close on the leading side; the audio route and the overflow, which holds Eject, trailing.
    private var topBar: some View {
        HStack(spacing: 4) {
            Button("Close", systemImage: "chevron.down", action: close)
                .labelStyle(.iconOnly)
                .font(.title3.weight(.semibold))
                .foregroundStyle(palette.text)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
                .accessibilityHint("Keeps playing")
            Spacer()
            RoutePicker(tint: UIColor(palette.text), activeTint: UIColor(palette.canvasAction))
                .frame(width: 44, height: 44)
            Menu {
                Button("Eject", systemImage: "eject") { Task { await app.eject() } }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(palette.text)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("More")
        }
        .frame(minHeight: 44)
    }

    private var metadata: some View {
        VStack(spacing: 4) {
            Text(model.title)
                .serifTitle(28, relativeTo: .title)
                .foregroundStyle(palette.text)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                .accessibilityAddTraits(.isHeader)
            if let author = model.author {
                Text(author)
                    .font(.system(.body, design: .serif).italic())
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private func pocket(width: CGFloat) -> some View {
        PocketDrawing(
            title: model.title,
            throughBook: model.knownSeconds.map { elapsed / $0 } ?? 0,
            isPlaying: model.isPlaying, speed: Double(model.speed)
        )
        .frame(width: max(width, 160), height: max(width, 160) / PocketDrawing.ratio)
        // The title and author are read above; the player is decoration.
        .accessibilityHidden(true)
    }

    /// What can be read and done: the place, the scrubber, transport and utilities, or why the
    /// audiobook won't play.
    @ViewBuilder private var functional: some View {
        switch model.state {
        case .opening:
            ProgressView("Opening…")
                .tint(palette.text)
                .foregroundStyle(palette.textSecondary)
                .padding(.vertical, 32)
        case let .failed(message):
            VStack(spacing: 12) {
                ContentUnavailableView("Can't play this audiobook", systemImage: "exclamationmark.triangle", description: Text(message))
                Button("Close", action: close)
                    .buttonStyle(OutlinedActionStyle(fillsWidth: false))
            }
        case .ready:
            VStack(spacing: 0) {
                if let place = model.placeName {
                    Text(place)
                        .font(.system(.title3, design: .serif))
                        .foregroundStyle(palette.text)
                        .multilineTextAlignment(.center)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                        .padding(.bottom, 8)
                }
                problemNote
                scrubber
                times
                    .padding(.top, 2)
                transport
                    .padding(.top, 16)
                utilities
                    .padding(.top, 16)
            }
        }
    }

    @ViewBuilder private var problemNote: some View {
        if let problem = model.problem {
            PaperTag(edge: Theme.ribbon) {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(Theme.label(.subheadline))
                    .foregroundStyle(palette.ink)
            }
            .padding(.bottom, 12)
        }
    }

    /// Whole-book time: a drag previews the place and lets go to move there. VoiceOver adjusts
    /// it a skip at a time. Unknown until the length is.
    private var scrubber: some View {
        let total = model.knownSeconds
        let fraction = total.map { min(max(elapsed / $0, 0), 1) } ?? 0
        return GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(palette.boundary).frame(height: 4)
                Capsule().fill(palette.accent).frame(width: width * fraction, height: 4)
                if total != nil {
                    Circle()
                        .fill(palette.raised)
                        .overlay { Circle().strokeBorder(palette.accent, lineWidth: 2) }
                        .frame(width: 18, height: 18)
                        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                        .offset(x: width * fraction - 9)
                }
            }
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard let total, width > 0 else { return }
                        scrubbing = min(max(drag.location.x / width, 0), 1) * total
                    }
                    .onEnded { _ in
                        if let scrubbing { model.seek(to: .seconds(scrubbing)) }
                        scrubbing = nil
                    }
            )
        }
        .frame(height: 44)
        .disabled(total == nil)
        .accessibilityElement()
        .accessibilityLabel("Position")
        .accessibilityValue(total.map { "\(AudiobookPlayerView.format(elapsed)) of \(AudiobookPlayerView.format($0))" } ?? "Unknown")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: model.skip(by: model.skipForward)
            case .decrement: model.skip(by: .zero - model.skipBack)
            @unknown default: break
            }
        }
    }

    /// Elapsed and remaining, both of the whole Book file, like the scrubber.
    private var times: some View {
        HStack {
            Text(model.knownSeconds == nil ? "—" : AudiobookPlayerView.format(elapsed))
            Spacer()
            Text(model.knownSeconds.map { "-" + AudiobookPlayerView.format(max(0, $0 - elapsed)) } ?? "—")
        }
        .font(.footnote)
        .monospacedDigit()
        .foregroundStyle(palette.textSecondary)
        .accessibilityHidden(true)
    }

    private var transport: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            skipButton(back: true)
            Spacer(minLength: 16)
            Button {
                model.togglePlayback()
            } label: {
                ZStack {
                    Circle().fill(palette.accent)
                    if model.isBuffering {
                        ProgressView().tint(palette.onAccent)
                    } else {
                        Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(palette.onAccent)
                            // Optically centred: a play triangle sits left of its box.
                            .offset(x: model.isPlaying ? 0 : 2)
                    }
                }
                .frame(width: 68, height: 68)
                .contentShape(.circle)
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
            .accessibilityValue(model.isBuffering ? "Loading" : "")
            .sensoryFeedback(.impact, trigger: model.isPlaying)
            Spacer(minLength: 16)
            skipButton(back: false)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 320)
    }

    private func skipButton(back: Bool) -> some View {
        let interval = back ? model.skipBack : model.skipForward
        let seconds = Int(interval.seconds)
        return Button {
            model.skip(by: back ? .zero - interval : interval)
        } label: {
            Image(systemName: Self.skipSymbol(back: back, seconds: seconds))
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(palette.text)
                .frame(width: 48, height: 48)
                .contentShape(.rect)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(back ? "Back \(seconds) seconds" : "Forward \(seconds) seconds")
    }

    /// The numbered arrow for every skip Settings offers; a plain one for anything else.
    private static func skipSymbol(back: Bool, seconds: Int) -> String {
        let base = back ? "gobackward" : "goforward"
        return [10, 15, 30, 45, 60].contains(seconds) ? "\(base).\(seconds)" : base
    }

    /// Speed, the sleep timer and the contents, as labelled outlines, wrapping when narrow.
    private var utilities: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { utilityItems }
            VStack(spacing: 8) { utilityItems }
        }
    }

    @ViewBuilder private var utilityItems: some View {
        Menu {
            Picker("Speed", selection: Binding { model.speed } set: { model.setSpeed($0) }) {
                ForEach(ListeningSettings.speeds, id: \.self) { speed in
                    Text(AudiobookPlayerView.format(speed: speed)).tag(speed)
                }
            }
        } label: {
            UtilityLabel(text: AudiobookPlayerView.format(speed: model.speed), systemImage: nil)
        }
        .accessibilityLabel("Speed, \(AudiobookPlayerView.format(speed: model.speed))")
        Menu {
            SleepTimerChoices(model: model)
        } label: {
            UtilityLabel(text: model.sleepTimer == nil ? "Sleep timer" : model.sleepLabel, systemImage: "moon", isActive: model.sleepTimer != nil)
        }
        .accessibilityLabel(model.sleepTimer == nil ? "Sleep timer" : "Sleep timer, \(model.sleepLabel)")
        if model.hasContents {
            Button(action: showContents) {
                UtilityLabel(text: model.contentsName, systemImage: model.contentsIcon)
            }
            .buttonStyle(.plain)
        }
    }
}

/// A utility's label: an outline in the strong control boundary, lettered like the canvas.
private struct UtilityLabel: View {
    let text: String
    let systemImage: String?
    var isActive = false

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: isActive ? systemImage + ".fill" : systemImage)
            }
            Text(text)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(palette.text)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background {
            Capsule().fill(isActive ? palette.accent.opacity(0.16) : .clear)
            Capsule().strokeBorder(palette.boundary, lineWidth: 1)
        }
        .contentShape(.capsule)
    }
}

/// Dims a control while it's held.
private struct PressStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(!isEnabled ? 0.4 : configuration.isPressed ? 0.75 : 1)
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
    }
}

/// The portable tape player: a rounded shell in the theme's plastic with its strap, a dark
/// window onto the loaded cassette, whose label carries the Book's title, and a speaker grille.
/// Its hubs turn while the tape plays, unless Reduce Motion is on.
struct PocketDrawing: View {
    /// Width over height, strap included.
    static let ratio: CGFloat = 1.3

    let title: String
    /// 0…1.
    let throughBook: Double
    let isPlaying: Bool
    let speed: Double

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let strap = h * 0.13
            let shellHeight = h - strap
            ZStack(alignment: .top) {
                // The strap, behind the shell.
                UnevenRoundedRectangle(topLeadingRadius: strap * 1.6, topTrailingRadius: strap * 1.6)
                    .stroke(palette.shellTrim, lineWidth: max(w * 0.018, 4))
                    .frame(width: w * 0.5, height: strap * 2.2)
                    .padding(.top, max(w * 0.009, 2))
                shell(width: w, height: shellHeight)
                    .padding(.top, strap)
            }
            .frame(width: w, height: h)
        }
    }

    private func shell(width w: CGFloat, height h: CGFloat) -> some View {
        let radius = w * 0.07
        let window = CGSize(width: w * 0.8, height: h * 0.56)
        return ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: radius)
                .fill(LinearGradient(colors: [palette.shell.mix(with: .white, by: 0.25), palette.shell], startPoint: .top, endPoint: .bottom))
                // The edge catching the light.
                .overlay { RoundedRectangle(cornerRadius: radius).strokeBorder(.white.opacity(0.6), lineWidth: 1.5).padding(1) }
                .overlay { RoundedRectangle(cornerRadius: radius).strokeBorder(palette.shellTrim.opacity(0.35), lineWidth: 1) }
                .shadow(color: .black.opacity(0.22), radius: 8, y: 6)
            HStack(alignment: .firstTextBaseline) {
                Text("DOGEAR")
                    .font(.system(size: max(w * 0.036, 9), weight: .semibold, design: .serif))
                    .tracking(2)
                Spacer()
                Text("PORTABLE CASSETTE PLAYER")
                    .font(.system(size: max(w * 0.022, 6), weight: .medium))
                    .tracking(0.6)
            }
            .foregroundStyle(palette.shellTrim)
            .padding(.horizontal, w * 0.1)
            .padding(.top, h * 0.06)
            cassetteWindow(window)
                .padding(.top, h * 0.15)
            grille(width: w * 0.2, height: h * 0.14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, w * 0.1)
                .padding(.top, h * 0.15 + window.height + h * 0.05)
        }
        .frame(width: w, height: h)
    }

    /// The dark window, the cassette's paper label and its two reels.
    private func cassetteWindow(_ size: CGSize) -> some View {
        let reelBox = size.height * 0.36
        let reels = TapeReels(throughBook: throughBook, hub: reelBox * 0.2, full: reelBox * 0.5)
        return VStack(spacing: size.height * 0.05) {
            Text(title)
                .font(.system(size: max(size.width * 0.07, 13), weight: .semibold, design: .serif).italic())
                .foregroundStyle(palette.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: size.height * 0.34)
                .background(palette.raised, in: .rect(cornerRadius: 3))
                .overlay(alignment: .bottom) { palette.accent.opacity(0.7).frame(height: 1).padding(.horizontal, 14).padding(.bottom, 5) }
            TimelineView(.animation(paused: !isPlaying || reduceMotion)) { timeline in
                // One turn every 2.4 s at 1×, faster with the speed.
                let angle = Angle.degrees(timeline.date.timeIntervalSinceReferenceDate * 150 * speed)
                HStack {
                    reel(tape: reels.supply, box: reelBox, angle: angle)
                    Spacer(minLength: 0)
                    reel(tape: reels.takeUp, box: reelBox, angle: angle)
                }
                .padding(.horizontal, size.width * 0.14)
            }
            .frame(height: reelBox)
        }
        .padding(size.width * 0.05)
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(LinearGradient(colors: Theme.window, startPoint: .top, endPoint: .bottom), in: .rect(cornerRadius: size.width * 0.05))
        .overlay {
            RoundedRectangle(cornerRadius: size.width * 0.05)
                .strokeBorder(palette.shellTrim.opacity(0.8), lineWidth: 3)
        }
        .overlay(alignment: .top) {
            if contrast != .increased {
                // Glare across the window's glass.
                LinearGradient(colors: [.white.opacity(0.1), .clear], startPoint: .top, endPoint: .center)
                    .clipShape(.rect(cornerRadius: size.width * 0.05))
                    .allowsHitTesting(false)
            }
        }
    }

    private func reel(tape radius: Double, box: CGFloat, angle: Angle) -> some View {
        ZStack {
            Circle().fill(Theme.tape).frame(width: radius * 2, height: radius * 2)
            Circle().fill(Color(hex: 0xEDE6D8)).frame(width: box * 0.42, height: box * 0.42)
            ForEach(0 ..< 3, id: \.self) { tooth in
                Capsule()
                    .fill(Color(hex: 0x2A1A10))
                    .frame(width: max(box * 0.05, 2), height: box * 0.32)
                    .rotationEffect(.degrees(Double(tooth) * 60))
            }
            .rotationEffect(-angle)
        }
        .frame(width: box, height: box)
    }

    private func grille(width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: height * 0.12) {
            ForEach(0 ..< 5, id: \.self) { _ in
                Capsule().fill(palette.shellTrim.opacity(0.45)).frame(height: max(height * 0.08, 1.5))
            }
        }
        .frame(width: width, height: height)
    }
}
