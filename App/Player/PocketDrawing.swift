import DogearCore
import SwiftUI

/// The portable tape player, drawn after the theme's rendering: a molded shell lit from the upper
/// left, a recessed window onto the loaded cassette, a speaker grille, and keys that work.
///
/// Each theme has its own machine. Walnut & Paper's has a leather strap, two knobs and its keys
/// in a tray; Oak & Daylight's sits in a green casing under a carry handle and shows the whole
/// cassette; Bookcloth & Tape's has its keys along the top edge and hangs on a lanyard.
///
/// The cassette's label carries the Book's title; the tape on its reels is how far through the
/// Book the listener is, and the hubs turn while it plays unless Reduce Motion is on.
///
/// Everything is laid out on a grid 1000 units wide, so the drawing keeps its proportions at
/// any size.
struct PocketDrawing: View {
    /// Width over height, strap and keys included.
    static let ratio: CGFloat = 1000 / 940

    let title: String
    let author: String?
    /// 0…1.
    let throughBook: Double
    let isPlaying: Bool
    let speed: Double
    let isReady: Bool
    let skipBack: () -> Void
    let togglePlayback: () -> Void
    let skipForward: () -> Void

    @Environment(\.palette) private var palette
    @Environment(\.colorSchemeContrast) private var contrast

    /// Warm shade for everything the light doesn't reach.
    private static let shade = Color(hex: 0x28140A)
    private static let sprig = Color(hex: 0x5E7A45)

    private var keyColor: Color {
        switch palette.theme {
        case .walnut: Color(hex: 0xB4452F)
        case .oak: Color(hex: 0x5F7A58)
        case .bookcloth: palette.accent
        }
    }

    private var onKey: Color { palette.theme == .bookcloth ? Color(hex: 0xFFF3DF) : palette.raised }

    var body: some View {
        GeometryReader { proxy in
            let u = proxy.size.width / 1000
            ZStack(alignment: .topLeading) {
                switch palette.theme {
                case .walnut: walnut(u)
                case .oak: oak(u)
                // Narrower, leaving room for the lanyard at its side.
                case .bookcloth: bookcloth(u * 0.94).offset(x: 60 * u)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
    }

    // MARK: Walnut & Paper

    @ViewBuilder private func walnut(_ u: CGFloat) -> some View {
        let top: CGFloat = 130
        // The leather strap, over the top from the ring.
        let strap = Path { path in
            path.move(to: CGPoint(x: 48 * u, y: 168 * u))
            path.addCurve(
                to: CGPoint(x: 560 * u, y: 96 * u),
                control1: CGPoint(x: 130 * u, y: 50 * u), control2: CGPoint(x: 430 * u, y: -20 * u)
            )
            path.addLine(to: CGPoint(x: 578 * u, y: 132 * u))
        }
        ZStack(alignment: .topLeading) {
            strap.stroke(Color(hex: 0x5E3219), style: StrokeStyle(lineWidth: 40 * u, lineCap: .round)).offset(y: 3 * u)
            strap.stroke(
                LinearGradient(colors: [Color(hex: 0xA9683F), Color(hex: 0x7B4526)], startPoint: .top, endPoint: .bottom),
                style: StrokeStyle(lineWidth: 38 * u, lineCap: .round)
            )
            strap.stroke(Color(hex: 0xFFE1BE).opacity(0.35), style: StrokeStyle(lineWidth: max(1.6 * u, 0.5), dash: [7 * u, 5 * u]))
                .offset(y: -12 * u)
        }
        .frame(width: 1000 * u, height: 300 * u, alignment: .topLeading)
        .shadow(color: Self.shade.opacity(0.3), radius: 2.5 * u, x: 3 * u, y: 6 * u)
        Knob(unit: u).at(665, top - 26, 95, 30, unit: u)
        Knob(unit: u).at(800, top - 42, 95, 46, unit: u)
        Molded(color: palette.shell, radius: 72, depth: 14, unit: u, grain: contrast != .increased)
            .at(0, top, 1000, 780, unit: u)
        // The molded step inside the edge.
        RoundedRectangle(cornerRadius: 58 * u, style: .continuous)
            .strokeBorder(.white.opacity(0.22), lineWidth: max(1.5 * u, 0.5))
            .at(16, top + 16, 968, 748, unit: u)
        // The ring the strap is looped through, hanging over the corner.
        Ellipse()
            .strokeBorder(
                LinearGradient(colors: [Color(hex: 0xD9D2C4), Color(hex: 0x8F877A), Color(hex: 0xC4BBAA)], startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: max(7 * u, 2)
            )
            .shadow(color: Self.shade.opacity(0.35), radius: u, x: 2 * u, y: 3 * u)
            .at(0, 137, 60, 156, unit: u)
        Text("DOGEAR")
            .font(.system(size: 40 * u, weight: .regular, design: .serif))
            .tracking(9 * u)
            .foregroundStyle(palette.shellTrim)
            .fixedSize()
            .frame(width: 400 * u, height: 50 * u, alignment: .leading)
            .offset(x: 118 * u, y: (top + 74) * u)
        VStack(alignment: .trailing, spacing: 2 * u) {
            Text("PORTABLE")
            Text("CASSETTE PLAYER")
        }
        .font(.system(size: 22 * u, weight: .medium))
        .tracking(1.5 * u)
        .foregroundStyle(palette.shellTrim.opacity(0.9))
        .fixedSize()
        .frame(width: 400 * u, height: 60 * u, alignment: .trailing)
        .offset(x: 512 * u, y: (top + 66) * u)
        tapeWindow(u, width: 836, height: 372, radius: 48, bezel: CGSize(width: 62, height: 50)) { size in
            let label = size.height * 0.44
            let hub = size.height * 0.215
            let reels = TapeReels(throughBook: throughBook, hub: Double(hub * 1.25), full: Double(size.height * 0.62))
            reel(tape: reels.supply, hub: hub).position(x: size.width * 0.27, y: size.height * 0.72)
            reel(tape: reels.takeUp, hub: hub).position(x: size.width * 0.73, y: size.height * 0.72)
            HStack(spacing: 0) {
                Sprig(color: Self.sprig).frame(width: label * 0.84, height: label * 0.84)
                labelTitle(size: label * 0.5, color: palette.ink)
                Sprig(color: Self.sprig).frame(width: label * 0.84, height: label * 0.84).scaleEffect(x: -1)
            }
            .padding(.horizontal, size.width * 0.03)
            .frame(width: size.width, height: label)
            .background { paper(to: Color(hex: 0xE3D0AC), by: 0.6) }
            .shadow(color: .black.opacity(0.55), radius: 2.5 * u, y: 3 * u)
        }
        .at(82, top + 165, 836, 372, unit: u)
        Grille(shell: palette.shell, unit: u).at(82, top + 592, 180, 128, unit: u)
        // The keys in their tray.
        RoundedRectangle(cornerRadius: 22 * u, style: .continuous)
            .fill(
                LinearGradient(colors: [Color(hex: 0x2A2019), Color(hex: 0x43362B)], startPoint: .top, endPoint: .bottom)
                    .shadow(.inner(color: .black.opacity(0.6), radius: 2 * u, y: 3 * u))
            )
            .shadow(color: .white.opacity(0.55), radius: 0, y: 1.5 * u)
            .at(326, top + 582, 580, 148, unit: u)
        key("backward.fill", u, action: skipBack).at(331, top + 587, 168, 133, unit: u)
        key(isPlaying ? "pause.fill" : "play.fill", u, isMain: true, isDown: isPlaying, action: togglePlayback)
            .at(503, top + 587, 226, 133, unit: u)
        key("forward.fill", u, action: skipForward).at(733, top + 587, 168, 133, unit: u)
    }

    // MARK: Oak & Daylight

    @ViewBuilder private func oak(_ u: CGFloat) -> some View {
        let top: CGFloat = 120
        let trim = palette.shellTrim
        let handle = Path { path in
            path.move(to: CGPoint(x: 62 * u, y: 150 * u))
            path.addCurve(
                to: CGPoint(x: 938 * u, y: 150 * u),
                control1: CGPoint(x: 62 * u, y: -30 * u), control2: CGPoint(x: 938 * u, y: -30 * u)
            )
        }
        ZStack(alignment: .topLeading) {
            handle.stroke(
                LinearGradient(colors: [trim.mix(with: .white, by: 0.22), trim.mix(with: .black, by: 0.18)], startPoint: .top, endPoint: .bottom),
                lineWidth: 44 * u
            )
            handle.stroke(.white.opacity(0.18), lineWidth: max(3 * u, 0.75)).offset(y: -14 * u)
            Ferrule().frame(width: 56 * u, height: 50 * u).rotationEffect(.degrees(-8)).offset(x: 34 * u, y: 92 * u)
            Ferrule().frame(width: 56 * u, height: 50 * u).rotationEffect(.degrees(8)).offset(x: 910 * u, y: 92 * u)
        }
        .frame(width: 1000 * u, height: 300 * u, alignment: .topLeading)
        .shadow(color: Self.shade.opacity(0.28), radius: 3 * u, x: 4 * u, y: 8 * u)
        // The volume wheel on its side.
        RoundedRectangle(cornerRadius: 8 * u)
            .fill(LinearGradient(colors: [palette.shell.mix(with: .black, by: 0.1), palette.shell.mix(with: .white, by: 0.3)], startPoint: .leading, endPoint: .trailing))
            .overlay {
                VStack(spacing: 6 * u) {
                    ForEach(0 ..< 18, id: \.self) { _ in Color.black.opacity(0.18).frame(height: max(2 * u, 0.5)) }
                }
                .clipShape(.rect(cornerRadius: 8 * u))
            }
            .shadow(color: Self.shade.opacity(0.3), radius: 2 * u, x: 2 * u, y: 3 * u)
            .at(978, top + 150, 30, 150, unit: u)
        // The green casing, and the cream face set into it.
        Molded(color: trim, radius: 84, depth: 14, unit: u, grain: false).at(0, top, 1000, 800, unit: u)
        Molded(color: palette.shell, radius: 66, depth: 0, unit: u, grain: contrast != .increased)
            .shadow(color: Color(hex: 0x1E2814).opacity(0.3), radius: 2.5 * u, y: 4 * u)
            .at(30, top + 8, 944, 760, unit: u)
        Text("Dogear")
            .font(.system(size: 56 * u, weight: .bold, design: .serif).italic())
            .foregroundStyle(palette.ink.mix(with: trim, by: 0.3))
            .fixedSize()
            .frame(width: 400 * u, height: 70 * u, alignment: .leading)
            .offset(x: 150 * u, y: (top + 44) * u)
        Text("CASSETTE PLAYER")
            .font(.system(size: 19 * u, weight: .medium))
            .tracking(4 * u)
            .foregroundStyle(palette.ink.opacity(0.75))
            .fixedSize()
            .frame(width: 400 * u, height: 30 * u, alignment: .trailing)
            .offset(x: 460 * u, y: (top + 68) * u)
        oakCassette(u).at(86, top + 140, 828, 440, unit: u)
        Grille(shell: palette.shell, unit: u).at(96, top + 618, 160, 118, unit: u)
        key("backward.fill", u, action: skipBack).at(322, top + 620, 160, 119, unit: u)
        key(isPlaying ? "pause.fill" : "play.fill", u, isMain: true, isDown: isPlaying, action: togglePlayback)
            .at(498, top + 606, 226, 141, unit: u)
        key("forward.fill", u, action: skipForward).at(740, top + 620, 160, 119, unit: u)
    }

    /// The whole cassette behind the door: smoked shell, screws, and a paper label with the
    /// reels showing through its window.
    private func oakCassette(_ u: CGFloat) -> some View {
        let w: CGFloat = 828 * u
        let h: CGFloat = 440 * u
        let labelSize = CGSize(width: w - 88 * u, height: h - 118 * u)
        let reelWindow = CGSize(width: labelSize.width * 0.72, height: labelSize.height * 0.36)
        let hub = reelWindow.height * 0.4
        let shape = RoundedRectangle(cornerRadius: 30 * u, style: .continuous)
        return ZStack(alignment: .topLeading) {
            shape.fill(
                LinearGradient(colors: [Color(hex: 0x4A4741), Color(hex: 0x5D5A52), Color(hex: 0x3F3C37)], startPoint: .top, endPoint: .bottom)
                    .shadow(.inner(color: .black.opacity(0.6), radius: 6 * u, y: 8 * u))
            )
            ForEach(0 ..< 4, id: \.self) { corner in
                Circle()
                    .fill(RadialGradient(colors: [Color(hex: 0x8A867D), Color(hex: 0x3B3833)], center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: 9 * u))
                    .frame(width: 18 * u, height: 18 * u)
                    .position(x: corner % 2 == 0 ? 26 * u : w - 26 * u, y: corner < 2 ? 26 * u : h - 26 * u)
            }
            // Where the tape runs past the heads.
            Trapezoid()
                .fill(LinearGradient(colors: [Color(hex: 0x3A3732), Color(hex: 0x55514A)], startPoint: .top, endPoint: .bottom))
                .frame(width: w * 0.6, height: 70 * u)
                .offset(x: w * 0.2, y: h - 62 * u)
            ZStack {
                paper(to: Color(hex: 0xE6D8BC), by: 0.55)
                VStack(spacing: 0) {
                    labelTitle(size: labelSize.height * 0.19, color: palette.shellTrim, weight: .bold)
                        .padding(.horizontal, labelSize.width * 0.06)
                        .frame(height: labelSize.height * 0.36)
                    HStack(spacing: 0) {
                        Sprig(color: Color(hex: 0x6F8A57), bloom: Color(hex: 0xE9C46A))
                            .frame(width: labelSize.width * 0.12, height: labelSize.height * 0.44)
                        Spacer(minLength: 0)
                        ZStack {
                            Capsule().fill(
                                LinearGradient(colors: [Color(hex: 0x2C2925), Color(hex: 0x48443D)], startPoint: .top, endPoint: .bottom)
                                    .shadow(.inner(color: .black.opacity(0.7), radius: 3 * u, y: 4 * u))
                            )
                            RoundedRectangle(cornerRadius: 6 * u)
                                .fill(
                                    LinearGradient(colors: [Color(hex: 0x5A4A36), Color(hex: 0x7A6447), Color(hex: 0x4F402E)], startPoint: .top, endPoint: .bottom)
                                        .shadow(.inner(color: .black.opacity(0.6), radius: 2 * u, y: 2 * u))
                                )
                                .frame(width: reelWindow.width * 0.4, height: reelWindow.height * 0.72)
                            HStack {
                                reel(tape: Double(hub), hub: hub)
                                Spacer(minLength: 0)
                                reel(tape: Double(hub), hub: hub)
                            }
                            .padding(.horizontal, reelWindow.height * 0.1)
                        }
                        .frame(width: reelWindow.width, height: reelWindow.height)
                        .shadow(color: .white.opacity(0.8), radius: 0, y: 1.5 * u)
                        Spacer(minLength: 0)
                        Sprig(color: Color(hex: 0x6F8A57), bloom: Color(hex: 0xD98A74))
                            .frame(width: labelSize.width * 0.12, height: labelSize.height * 0.44)
                            .scaleEffect(x: -1)
                    }
                    .padding(.horizontal, labelSize.width * 0.015)
                    .frame(height: labelSize.height * 0.44)
                    Text(author ?? "")
                        .font(.system(size: labelSize.height * 0.1, design: .serif))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, labelSize.width * 0.08)
                        .frame(height: labelSize.height * 0.2)
                }
            }
            .frame(width: labelSize.width, height: labelSize.height)
            .clipShape(CutCorners())
            .offset(x: 44 * u, y: 40 * u)
            if contrast != .increased { Glare().clipShape(shape).allowsHitTesting(false) }
        }
        .frame(width: w, height: h, alignment: .topLeading)
        .clipShape(shape)
        .background { Recess(shell: palette.shell, radius: 35 * u).padding(-5 * u) }
    }

    // MARK: Bookcloth & Tape

    @ViewBuilder private func bookcloth(_ u: CGFloat) -> some View {
        let top: CGFloat = 150
        let cord = Path { path in
            path.move(to: CGPoint(x: 50 * u, y: 215 * u))
            path.addCurve(
                to: CGPoint(x: -36 * u, y: 420 * u),
                control1: CGPoint(x: -10 * u, y: 230 * u), control2: CGPoint(x: -30 * u, y: 300 * u)
            )
            path.addLine(to: CGPoint(x: -48 * u, y: 800 * u))
            path.addCurve(
                to: CGPoint(x: 28 * u, y: 800 * u),
                control1: CGPoint(x: -50 * u, y: 880 * u), control2: CGPoint(x: 26 * u, y: 880 * u)
            )
            path.addLine(to: CGPoint(x: 34 * u, y: 330 * u))
        }
        // The lanyard, hanging from its corner.
        ZStack(alignment: .topLeading) {
            cord.stroke(keyColor.mix(with: .black, by: 0.3), style: StrokeStyle(lineWidth: 30 * u, lineCap: .round))
                .offset(x: 2 * u, y: 3 * u)
            cord.stroke(keyColor, style: StrokeStyle(lineWidth: 28 * u, lineCap: .round))
            cord.stroke(.white.opacity(0.18), style: StrokeStyle(lineWidth: max(2 * u, 0.5), dash: [3 * u, 4 * u]))
            RoundedRectangle(cornerRadius: 10 * u)
                .fill(LinearGradient(colors: [Color(hex: 0xD9C8A6), Color(hex: 0xB9A682)], startPoint: .top, endPoint: .bottom))
                .frame(width: 62 * u, height: 74 * u)
                .rotationEffect(.degrees(14))
                .offset(x: -24 * u, y: 238 * u)
        }
        .frame(width: 1000 * u, height: 940 * u, alignment: .topLeading)
        .shadow(color: .black.opacity(0.4), radius: 2 * u, x: 3 * u, y: 5 * u)
        // The keys stand along the top edge.
        RoundedRectangle(cornerRadius: 10 * u).fill(Color(hex: 0x2E2A24)).at(150, top - 18, 700, 40, unit: u)
        key("backward.fill", u, action: skipBack).at(158, top - 90, 160, 127, unit: u)
        key("stop.fill", u, action: { if isPlaying { togglePlayback() } }).at(326, top - 90, 170, 127, unit: u)
        key(isPlaying ? "pause.fill" : "play.fill", u, isMain: true, isDown: isPlaying, action: togglePlayback)
            .at(504, top - 108, 190, 145, unit: u)
        key("forward.fill", u, action: skipForward).at(702, top - 90, 142, 127, unit: u)
        Molded(color: palette.shell, radius: 80, depth: 14, unit: u, grain: contrast != .increased, shadow: .black)
            .at(0, top, 1000, 740, unit: u)
        RoundedRectangle(cornerRadius: 66 * u, style: .continuous)
            .strokeBorder(.white.opacity(0.22), lineWidth: max(1.5 * u, 0.5))
            .at(16, top + 16, 968, 708, unit: u)
        tapeWindow(u, width: 816, height: 420, radius: 52, bezel: CGSize(width: 44, height: 30)) { size in
            let label = size.height * 0.56
            let hub = size.height * 0.17
            let middle = label + (size.height - label) * 0.52
            let reels = TapeReels(throughBook: throughBook, hub: Double(hub * 1.25), full: Double(size.height * 0.36))
            reel(tape: reels.supply, hub: hub).position(x: size.width * 0.27, y: middle)
            reel(tape: reels.takeUp, hub: hub).position(x: size.width * 0.73, y: middle)
            // The tape between the reels, behind its own little window.
            RoundedRectangle(cornerRadius: 5 * u)
                .fill(
                    LinearGradient(colors: [Color(hex: 0x2C3430), Color(hex: 0x465049), Color(hex: 0x262D2A)], startPoint: .top, endPoint: .bottom)
                        .shadow(.inner(color: .black.opacity(0.6), radius: 2 * u, y: 2 * u))
                )
                .frame(width: size.width * 0.2, height: hub * 1.8)
                .position(x: size.width * 0.5, y: middle)
            VStack(spacing: 0) {
                labelTitle(size: label * 0.3, color: Color(hex: 0x1D1A16))
                    .frame(height: label * 0.56)
                keyColor.opacity(0.8).frame(height: max(2.5 * u, 0.75))
                Text(author ?? "")
                    .font(.system(size: label * 0.17, design: .serif).italic())
                    .foregroundStyle(Color(hex: 0x1D1A16))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(height: label * 0.36)
            }
            .padding(.horizontal, size.width * 0.08)
            .frame(width: size.width, height: label, alignment: .top)
            .background { paper(to: Color(hex: 0xDFCBA6), by: 0.5) }
            .clipShape(.rect(bottomLeadingRadius: 8 * u, bottomTrailingRadius: 8 * u))
            .shadow(color: .black.opacity(0.55), radius: 2.5 * u, y: 3 * u)
        }
        .at(92, top + 120, 816, 420, unit: u)
        // A dot grille, and two ribs.
        Canvas { context, _ in
            for row in 0 ..< 5 {
                for column in 0 ..< (11 - row % 2) {
                    let x = (CGFloat(column) * 22 + CGFloat(row % 2) * 11) * u
                    let y = CGFloat(row) * 21 * u
                    let hole = CGRect(x: x, y: y, width: 11 * u, height: 11 * u)
                    context.fill(Path(ellipseIn: hole.offsetBy(dx: 0, dy: 1.2 * u)), with: .color(.white.opacity(0.55)))
                    context.fill(Path(ellipseIn: hole), with: .color(palette.shell.mix(with: Color(hex: 0x1F1408), by: 0.72)))
                }
            }
        }
        .at(104, top + 590, 240, 100, unit: u)
        ForEach([636, 672], id: \.self) { y in
            Rib(shell: palette.shell, unit: u, depth: 0.3).at(660, top + CGFloat(y), 250, 9, unit: u)
        }
    }

    // MARK: Parts

    /// A recessed window with a dark bezel, and behind its glass whatever `contents` draws in
    /// the space it is given.
    private func tapeWindow<Contents: View>(
        _ u: CGFloat, width: CGFloat, height: CGFloat, radius: CGFloat, bezel: CGSize,
        @ViewBuilder contents: (CGSize) -> Contents
    ) -> some View {
        let outer = RoundedRectangle(cornerRadius: radius * u, style: .continuous)
        let glass = RoundedRectangle(cornerRadius: 10 * u, style: .continuous)
        let size = CGSize(width: (width - bezel.width * 2) * u, height: (height - bezel.height * 2) * u)
        return ZStack {
            outer.fill(
                LinearGradient(colors: [Color(hex: 0x2B2B2A), Color(hex: 0x3A3938), Color(hex: 0x2E2D2C)], startPoint: .top, endPoint: .bottom)
                    .shadow(.inner(color: .black.opacity(0.7), radius: 3 * u, y: 4 * u))
            )
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [Color(hex: 0x1B1512), Color(hex: 0x2A201A), Color(hex: 0x17110E)], startPoint: .top, endPoint: .bottom)
                contents(size)
                // The window's depth over the cassette, and light on the glass.
                glass.stroke(.black.opacity(0.6), lineWidth: 10 * u).blur(radius: 5 * u).offset(y: 3 * u)
                    .frame(width: size.width, height: size.height)
                if contrast != .increased { Glare() }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipShape(glass)
            // The lip of the window catching light.
            outer.strokeBorder(.white.opacity(0.16), lineWidth: max(2.5 * u, 0.75))
        }
        .background { Recess(shell: palette.shell, radius: (radius + 5) * u).padding(-5 * u) }
    }

    private func labelTitle(size: CGFloat, color: Color, weight: Font.Weight = .medium) -> some View {
        Text(title)
            .font(.system(size: max(size, 10), weight: weight, design: .serif).italic())
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity)
    }

    /// Label paper, a little aged toward its foot.
    private func paper(to aged: Color, by amount: Double) -> some View {
        LinearGradient(
            colors: [palette.raised.mix(with: aged, by: amount * 0.5), palette.raised.mix(with: aged, by: amount)],
            startPoint: .top, endPoint: .bottom
        )
    }

    private func reel(tape: Double, hub: CGFloat) -> some View {
        Reel(tape: CGFloat(tape), hub: hub, isPlaying: isPlaying, speed: speed)
    }

    private func key(_ symbol: String, _ u: CGFloat, isMain: Bool = false, isDown: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: (isMain ? 50 : 40) * u, weight: .semibold))
                .foregroundStyle(isMain ? onKey : palette.ink.mix(with: palette.shell, by: 0.12))
        }
        .buttonStyle(ShellKeyStyle(
            face: isMain ? keyColor : palette.shell.mix(with: .white, by: 0.38),
            lip: isMain ? keyColor.mix(with: .black, by: 0.38) : palette.shell.mix(with: Color(hex: 0x3A2A1A), by: 0.42),
            isMain: isMain, isDown: isDown, unit: u
        ))
        .disabled(!isReady)
    }
}

private extension View {
    /// Placed on the drawing's grid: a frame of `width` by `height` units with its corner at
    /// (`x`, `y`), inside a top-leading stack.
    func at(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, unit: CGFloat) -> some View {
        frame(width: width * unit, height: height * unit).offset(x: x * unit, y: y * unit)
    }
}

/// A piece of molded plastic: lighter where it faces the light, its edges rolling away, standing
/// `depth` off the surface it lies on.
private struct Molded: View {
    let color: Color
    let radius: CGFloat
    let depth: CGFloat
    let unit: CGFloat
    let grain: Bool
    var shadow = Color(hex: 0x28140A)

    var body: some View {
        let u = unit
        let shape = RoundedRectangle(cornerRadius: radius * u, style: .continuous)
        ZStack {
            if depth > 0 {
                shape
                    .fill(color.mix(with: Color(hex: 0x2A1A0C), by: 0.45))
                    .offset(y: depth * u)
                    .shadow(color: shadow.opacity(0.3), radius: 19 * u, x: 10 * u, y: 26 * u)
                    .shadow(color: shadow.opacity(0.28), radius: 4 * u, x: 2 * u, y: 5 * u)
            }
            shape.fill(
                LinearGradient(
                    stops: [
                        .init(color: color.mix(with: .white, by: 0.22), location: 0),
                        .init(color: color, location: 0.38),
                        .init(color: color.mix(with: Color(hex: 0x6B4A2A), by: 0.1), location: 1),
                    ],
                    startPoint: UnitPoint(x: 0.45, y: 0), endPoint: UnitPoint(x: 0.55, y: 1)
                )
                .shadow(.inner(color: .white.opacity(0.7), radius: 2 * u, x: 2 * u, y: 3 * u))
                .shadow(.inner(color: Color(hex: 0x503214).opacity(0.24), radius: 5 * u, x: -4 * u, y: -6 * u))
            )
            if grain {
                Speckle(density: 9, opacity: 0.035).clipShape(shape)
            }
        }
    }
}

/// The edge of a hole in the shell: in shade along its top, catching light along its foot.
private struct Recess: View {
    let shell: Color
    let radius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(LinearGradient(
                stops: [
                    .init(color: shell.mix(with: Color(hex: 0x3A2510), by: 0.5), location: 0),
                    .init(color: shell.mix(with: Color(hex: 0x3A2510), by: 0.2), location: 0.3),
                    .init(color: shell.mix(with: .white, by: 0.6), location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            ))
    }
}

/// Light across a pane of glass.
private struct Glare: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(0.1), location: 0), .init(color: .clear, location: 0.28),
                .init(color: .clear, location: 0.72), .init(color: .white.opacity(0.05), location: 1),
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
}

/// One reel: brown tape wound to `tape`, and a cream hub of radius `hub` whose teeth turn.
private struct Reel: View {
    let tape: CGFloat
    let hub: CGFloat
    let isPlaying: Bool
    let speed: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [Color(hex: 0x5A3A26), Color(hex: 0x4A2D1C), Color(hex: 0x34200F)],
                    center: .center, startRadius: 0, endRadius: max(tape, 1)
                ))
                .overlay {
                    // The windings.
                    ForEach([0.93, 0.84, 0.74, 0.63], id: \.self) { share in
                        Circle().stroke(.black.opacity(0.16), lineWidth: 0.5).frame(width: tape * 2 * share, height: tape * 2 * share)
                    }
                }
                .frame(width: tape * 2, height: tape * 2)
                .shadow(color: .black.opacity(0.5), radius: 2)
            Circle()
                .fill(
                    LinearGradient(colors: [Color(hex: 0xEFE7D8), Color(hex: 0xC9BDA8), Color(hex: 0xB3A792)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .shadow(.inner(color: .white.opacity(0.7), radius: 0.5, y: 0.75))
                        .shadow(.inner(color: .black.opacity(0.18), radius: 1, y: -1))
                )
                .frame(width: hub * 2, height: hub * 2)
                .shadow(color: .black.opacity(0.45), radius: 1.5, y: 1)
            Circle()
                .strokeBorder(Color(hex: 0x5A4B37).opacity(0.35), lineWidth: 0.5)
                .frame(width: hub * 1.52, height: hub * 1.52)
            // The spindle hole.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: 0x55504B), Color(hex: 0x26221F), Color(hex: 0x121010)],
                        center: UnitPoint(x: 0.4, y: 0.32), startRadius: 0, endRadius: hub * 0.6
                    )
                    .shadow(.inner(color: .black.opacity(0.7), radius: 1.5, y: 1))
                )
                .frame(width: hub * 1.12, height: hub * 1.12)
                .shadow(color: .white.opacity(0.5), radius: 0, y: 0.5)
            TimelineView(.animation(paused: !isPlaying || reduceMotion)) { timeline in
                // One turn every 2.4 s at 1×, faster with the speed.
                let turn = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate * 150 * speed
                ZStack {
                    ForEach(0 ..< 6, id: \.self) { tooth in
                        RoundedRectangle(cornerRadius: hub * 0.04)
                            .fill(Color(hex: 0xD8CEBC))
                            .frame(width: hub * 0.2, height: hub * 0.2)
                            .offset(y: -hub * 0.5)
                            .rotationEffect(.degrees(Double(tooth) * 60))
                    }
                }
                .rotationEffect(.degrees(-turn.truncatingRemainder(dividingBy: 360)))
            }
            .frame(width: hub * 2, height: hub * 2)
        }
        .frame(width: hub * 2, height: hub * 2)
    }
}

/// A sprig printed on a label: a stem with five leaves, and a flower at its tip when `bloom`
/// is given.
private struct Sprig: View {
    let color: Color
    var bloom: Color?

    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height) / 100
            ZStack(alignment: .topLeading) {
                Stem().stroke(color, style: StrokeStyle(lineWidth: max(2.5 * s, 0.6), lineCap: .round))
                Leaves().fill(color)
                if let bloom {
                    Circle().fill(bloom.opacity(0.85)).frame(width: 26 * s, height: 26 * s).offset(x: 67 * s, y: -1 * s)
                    Circle().fill(bloom.mix(with: .white, by: 0.55)).frame(width: 10 * s, height: 10 * s).offset(x: 75 * s, y: 7 * s)
                }
            }
            .frame(width: 100 * s, height: 100 * s, alignment: .topLeading)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private struct Stem: Shape {
        func path(in rect: CGRect) -> Path {
            let s = min(rect.width, rect.height) / 100
            var path = Path()
            path.move(to: CGPoint(x: 18 * s, y: 92 * s))
            path.addCurve(
                to: CGPoint(x: 80 * s, y: 12 * s),
                control1: CGPoint(x: 34 * s, y: 70 * s), control2: CGPoint(x: 52 * s, y: 46 * s)
            )
            return path
        }
    }

    private struct Leaves: Shape {
        func path(in rect: CGRect) -> Path {
            let s = min(rect.width, rect.height) / 100
            var leaf = Path()
            leaf.move(to: .zero)
            leaf.addCurve(to: CGPoint(x: 24, y: 0), control1: CGPoint(x: 7, y: -6), control2: CGPoint(x: 17, y: -5))
            leaf.addCurve(to: .zero, control1: CGPoint(x: 17, y: 5), control2: CGPoint(x: 7, y: 6))
            leaf.closeSubpath()
            // Where each leaf joins the stem, and the way it points, in degrees.
            let leaves: [(x: CGFloat, y: CGFloat, turn: CGFloat)] = [
                (30, 78, -60), (42, 62, 20), (50, 48, -55), (60, 34, 25), (72, 20, -20),
            ]
            var path = Path()
            for placed in leaves {
                let transform = CGAffineTransform(scaleX: s, y: s)
                    .translatedBy(x: placed.x, y: placed.y)
                    .rotated(by: placed.turn * .pi / 180)
                path.addPath(leaf, transform: transform)
            }
            return path
        }
    }
}

/// Slots in the plastic over the speaker.
private struct Grille: View {
    let shell: Color
    let unit: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0 ..< 6, id: \.self) { index in
                if index > 0 { Spacer(minLength: 0) }
                Rib(shell: shell, unit: unit, depth: 0.5).frame(height: max(9 * unit, 2))
            }
        }
    }
}

/// One slot or groove, shaded inside and lit along its lower edge.
private struct Rib: View {
    let shell: Color
    let unit: CGFloat
    /// How dark the groove is, 0…1.
    let depth: Double

    var body: some View {
        Capsule()
            .fill(LinearGradient(
                colors: [shell.mix(with: Color(hex: 0x2F1C0A), by: depth + 0.12), shell.mix(with: Color(hex: 0x2F1C0A), by: depth - 0.1)],
                startPoint: .top, endPoint: .bottom
            ))
            .shadow(color: .white.opacity(0.6), radius: 0, y: max(1.5 * unit, 0.5))
    }
}

/// A knurled metal knob standing on the top edge.
private struct Knob: View {
    let unit: CGFloat

    var body: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 5 * unit, topTrailingRadius: 5 * unit)
        shape
            .fill(LinearGradient(
                colors: [Color(hex: 0x5D564E), Color(hex: 0xB7AFA3), Color(hex: 0x8D857B), Color(hex: 0x4B453F)],
                startPoint: .leading, endPoint: .trailing
            ))
            .overlay {
                HStack(spacing: 3.5 * unit) {
                    ForEach(0 ..< 19, id: \.self) { _ in Color.black.opacity(0.28).frame(width: max(1.5 * unit, 0.5)) }
                }
            }
            .overlay(alignment: .top) { Color.white.opacity(0.35).frame(height: max(2 * unit, 0.5)) }
            .clipShape(shape)
            .shadow(color: Color(hex: 0x28140A).opacity(0.3), radius: 2 * unit, x: 2 * unit, y: 2 * unit)
    }
}

/// The metal cuff at each end of the carry handle.
private struct Ferrule: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(LinearGradient(
                stops: [
                    .init(color: Color(hex: 0x8D877C), location: 0), .init(color: Color(hex: 0xECE6DA), location: 0.35),
                    .init(color: Color(hex: 0x9C958A), location: 0.7), .init(color: Color(hex: 0x6D675E), location: 1),
                ],
                startPoint: .leading, endPoint: .trailing
            ))
    }
}

/// A label with its two lower corners cut off.
private struct CutCorners: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.88))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.97, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.03, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.88))
        path.closeSubpath()
        return path
    }
}

/// Narrower at the top than at the foot.
private struct Trapezoid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.06, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.94, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// A key on the player: a softly domed face standing on a darker lip, which it sinks into when
/// pressed. The lip takes the bottom 5 units of the key's frame.
private struct ShellKeyStyle: ButtonStyle {
    let face: Color
    let lip: Color
    let isMain: Bool
    let isDown: Bool
    let unit: CGFloat

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let u = unit
        let down = isDown || configuration.isPressed
        let travel: CGFloat = down ? 1 : 5
        let shape = RoundedRectangle(cornerRadius: 16 * u, style: .continuous)
        configuration.label
            .opacity(isEnabled ? 1 : 0.45)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                shape
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: face.mix(with: .white, by: isMain ? 0.12 : 0.3), location: 0),
                                .init(color: face, location: 0.45),
                                .init(color: face.mix(with: .black, by: 0.07), location: 1),
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                        .shadow(.inner(color: .white.opacity(isMain ? 0.35 : 0.85), radius: 0.75 * u, x: u, y: 1.5 * u))
                        .shadow(.inner(color: .black.opacity(0.09), radius: 2 * u, x: -u, y: -3 * u))
                    )
                    .shadow(color: lip, radius: 0, y: travel * u)
                    .shadow(color: .black.opacity(0.35), radius: 2 * u, y: (travel + 2) * u)
            }
            .offset(y: down ? 4 * u : 0)
            .padding(.bottom, 5 * u)
            .contentShape(Rectangle())
            .animation(.snappy(duration: 0.1), value: down)
    }
}
