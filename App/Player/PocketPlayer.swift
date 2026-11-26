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
            ScrollView {
                arranged(PlayerArrangement(width: proxy.size.width, height: proxy.size.height, fold: proxy.fold), in: proxy.size)
                    .frame(maxWidth: .infinity)
            }
            // Pulled down past the top, the player closes like a sheet, and the tape plays on.
            .modifier(PullsDownToClose(close: close))
        }
    }

    /// The player's parts laid out for a screen `size` big, which may have a fold across it.
    @ViewBuilder private func arranged(_ arrangement: PlayerArrangement, in size: CGSize) -> some View {
        switch arrangement {
        case .column:
            // Spread down a tall screen rather than leaving its foot empty.
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 8)
                metadata
                Spacer(minLength: 16)
                pocket(width: min(size.width >= 560 ? 400 : 370, size.width - 32, max(size.height * 0.4, 170) * PocketDrawing.ratio))
                Spacer(minLength: 16)
                functional
                Spacer(minLength: 16)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .frame(maxWidth: 560, minHeight: size.height, alignment: .top)
        case .sideBySide(.none):
            // Side by side in a short, wide window, with the title and artwork together.
            let art = min(400, size.width - 32, max(size.height * 0.4, 170) * PocketDrawing.ratio)
            VStack(spacing: 0) {
                topBar
                HStack(alignment: .center, spacing: 32) {
                    VStack(spacing: 16) {
                        metadata
                        pocket(width: min(art, (size.width - 64) / 2))
                    }
                    .frame(maxWidth: .infinity)
                    functional
                        .frame(maxWidth: .infinity)
                }
                .padding(.top, 12)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .frame(maxWidth: 1040, minHeight: size.height, alignment: .top)
        case let .sideBySide(.some(split)):
            // Open like a book: the title and artwork on one page, the controls on the other.
            let leading = max(CGFloat(split.before) - 16, 0)
            let gap = CGFloat(split.gap)
            let trailing = max(size.width - CGFloat(split.before) - gap - 16, 0)
            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 16)
                HStack(alignment: .center, spacing: gap) {
                    VStack(spacing: 16) {
                        metadata
                        pocket(width: min(400, leading - 16, max(size.height * 0.4, 170) * PocketDrawing.ratio))
                    }
                    .frame(width: leading)
                    functional
                        .padding(.horizontal, 8)
                        .frame(width: trailing)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .padding(.bottom, 8)
            .frame(width: size.width)
            .frame(minHeight: size.height, alignment: .top)
        case let .aboveAndBelow(split):
            // Stood like a laptop: the player faces the listener, the controls lie flat to hand.
            let above = CGFloat(split.before)
            let gap = CGFloat(split.gap)
            let below = max(size.height - above - gap, 0)
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: 4)
                    metadata
                    Spacer(minLength: 8)
                    pocket(width: min(400, size.width - 32, max(above - 170, 110) * PocketDrawing.ratio))
                    Spacer(minLength: 8)
                }
                .frame(minHeight: above, alignment: .top)
                Color.clear
                    .frame(height: gap)
                    .accessibilityHidden(true)
                functional
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity, minHeight: below)
            }
            .padding(.horizontal, 16)
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
        .frame(width: max(width, 170), height: max(width, 170) / PocketDrawing.ratio)
        // The title and author are read above, and the transport row below is the working one.
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

