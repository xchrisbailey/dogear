import DogearCore
import SwiftUI

/// The portable tape player, drawn as the mockups show it: a molded shell in the theme's plastic
/// with a leather strap or carry handle, two knobs on top, a recessed window onto the loaded
/// cassette, a speaker grille, and three keys that work.
///
/// The cassette's label carries the Book's title; the tape on its reels is how far through the
/// Book the listener is, and the hubs turn while it plays unless Reduce Motion is on.
struct PocketDrawing: View {
    /// Width over height, strap and knobs included.
    static let ratio: CGFloat = 1.12

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

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let top = h * 0.12
            let shellHeight = h - top - h * 0.035
            ZStack(alignment: .topLeading) {
                if palette.theme == .walnut {
                    Strap(width: w, top: top)
                } else {
                    Handle(width: w, top: top)
                }
                if palette.theme != .oak {
                    knobs(width: w, top: top)
                }
                shell(width: w, height: shellHeight)
                    .offset(y: top)
            }
            .frame(width: w, height: h, alignment: .topLeading)
        }
    }

    // MARK: Shell

    private func shell(width w: CGFloat, height h: CGFloat) -> some View {
        let radius = w * 0.075
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let isOak = palette.theme == .oak
        let rim = isOak ? w * 0.028 : 0
        return ZStack(alignment: .topLeading) {
            // The shell's depth: its lower edge in shade, below the face.
            shape
                .fill((isOak ? palette.shellTrim : palette.shell).mix(with: .black, by: 0.3))
                .offset(y: h * 0.022)
            if isOak {
                // The colored casing around the face.
                shape.fill(LinearGradient(
                    colors: [palette.shellTrim.mix(with: .white, by: 0.22), palette.shellTrim, palette.shellTrim.mix(with: .black, by: 0.12)],
                    startPoint: .top, endPoint: .bottom
                ))
            }
            face(width: w - rim * 2, height: h - rim * 2, radius: radius - rim)
                .offset(x: rim, y: rim)
        }
        .frame(width: w, height: h, alignment: .topLeading)
        .compositingGroup()
        .shadow(color: .black.opacity(0.26), radius: 18, y: 14)
        .shadow(color: .black.opacity(0.18), radius: 2, y: 2)
    }

    private func face(width w: CGFloat, height h: CGFloat, radius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let window = CGSize(width: w * 0.86, height: h * 0.52)
        let row = h * 0.17
        return ZStack(alignment: .topLeading) {
            shape.fill(LinearGradient(
                colors: [palette.shell.mix(with: .white, by: 0.35), palette.shell, palette.shell.mix(with: .black, by: 0.07)],
                startPoint: .top, endPoint: .bottom
            ))
            if contrast != .increased {
                Speckle(density: 7, opacity: 0.05).clipShape(shape)
                // Light from the upper left across the molded plastic.
                RadialGradient(colors: [.white.opacity(0.35), .clear], center: UnitPoint(x: 0.2, y: 0.05), startRadius: 0, endRadius: w * 0.8)
                    .clipShape(shape)
            }
            shape.strokeBorder(
                LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0.15), .black.opacity(0.2)], startPoint: .top, endPoint: .bottom),
                lineWidth: 2
            )
            printing(width: w)
                .padding(.horizontal, w * 0.07)
                .padding(.top, h * 0.06)
            cassetteWindow(window)
                .offset(x: (w - window.width) / 2, y: h * 0.19)
            grille(width: w * 0.19, height: row * 0.8)
                .offset(x: w * 0.07, y: h * 0.19 + window.height + h * 0.08 + row * 0.1)
            keys(width: w * 0.6, height: row)
                .offset(x: w * 0.33, y: h * 0.19 + window.height + h * 0.08)
        }
        .frame(width: w, height: h, alignment: .topLeading)
    }

    /// The maker's name and model, printed on the plastic.
    private func printing(width w: CGFloat) -> some View {
        HStack(alignment: .top) {
            Text(palette.theme == .oak ? "Dogear" : "DOGEAR")
                .font(.system(size: max(w * 0.048, 11), weight: .medium, design: .serif))
                .italic(palette.theme == .oak)
                .tracking(palette.theme == .oak ? 0 : w * 0.012)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                if palette.theme != .oak { Text("PORTABLE") }
                Text("CASSETTE PLAYER")
            }
            .font(.system(size: max(w * 0.026, 7), weight: .medium))
            .tracking(1.2)
        }
        .foregroundStyle(palette.shellTrim.opacity(0.9))
        .frame(width: w * 0.86)
    }

    // MARK: Strap, handle, knobs

    /// A stitched leather strap from a ring at the corner over the top.
    private struct Strap: View {
        let width: CGFloat
        let top: CGFloat

        @Environment(\.palette) private var palette

        var body: some View {
            let w = width
            let path = Path { path in
                path.move(to: CGPoint(x: w * 0.045, y: top + w * 0.08))
                path.addCurve(
                    to: CGPoint(x: w * 0.56, y: top + 2),
                    control1: CGPoint(x: w * 0.06, y: top - w * 0.12),
                    control2: CGPoint(x: w * 0.5, y: top - w * 0.15)
                )
            }
            let leather = palette.shellTrim.mix(with: Color(hex: 0xB07A4A), by: 0.55)
            ZStack(alignment: .topLeading) {
                path.stroke(leather.mix(with: .black, by: 0.3), style: StrokeStyle(lineWidth: w * 0.05, lineCap: .round))
                    .offset(y: 1.5)
                path.stroke(leather, style: StrokeStyle(lineWidth: w * 0.045, lineCap: .round))
                path.stroke(.white.opacity(0.3), style: StrokeStyle(lineWidth: 0.8, dash: [3, 2.5]))
                // The ring the strap is looped through.
                Circle()
                    .strokeBorder(
                        LinearGradient(colors: [Color(hex: 0xE4E0D8), Color(hex: 0x8A8580), Color(hex: 0xC9C4BC)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: max(w * 0.01, 2.5)
                    )
                    .frame(width: w * 0.085, height: w * 0.085)
                    .offset(x: w * 0.0, y: top + w * 0.04)
            }
            .shadow(color: .black.opacity(0.2), radius: 2, y: 2)
        }
    }

    /// A padded carry handle across the top, held by metal clips at each end.
    private struct Handle: View {
        let width: CGFloat
        let top: CGFloat

        @Environment(\.palette) private var palette

        var body: some View {
            let w = width
            let thickness = max(w * 0.04, 8)
            let color = palette.theme == .bookcloth ? palette.accent : palette.shellTrim
            ZStack(alignment: .topLeading) {
                UnevenRoundedRectangle(topLeadingRadius: top * 1.4, topTrailingRadius: top * 1.4)
                    .stroke(color.mix(with: .black, by: 0.25), lineWidth: thickness)
                    .offset(y: 1.5)
                    .frame(width: w * 0.8, height: top * 1.6)
                    .offset(x: w * 0.1, y: thickness / 2)
                UnevenRoundedRectangle(topLeadingRadius: top * 1.4, topTrailingRadius: top * 1.4)
                    .stroke(
                        LinearGradient(colors: [color.mix(with: .white, by: 0.2), color], startPoint: .top, endPoint: .bottom),
                        lineWidth: thickness
                    )
                    .frame(width: w * 0.8, height: top * 1.6)
                    .offset(x: w * 0.1, y: thickness / 2)
                ForEach([0.1, 0.9], id: \.self) { x in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(LinearGradient(colors: [Color(hex: 0xE8E4DC), Color(hex: 0x8E8984), Color(hex: 0xD6D1C9)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: thickness * 1.6, height: top * 0.55)
                        .offset(x: w * x - thickness * 0.8, y: top * 0.55)
                }
            }
            .shadow(color: .black.opacity(0.18), radius: 2, y: 2)
        }
    }

    /// Two ridged knobs standing on the top edge.
    private func knobs(width w: CGFloat, top: CGFloat) -> some View {
        HStack(alignment: .bottom, spacing: w * 0.04) {
            knob(width: w * 0.075, height: top * 0.5)
            knob(width: w * 0.085, height: top * 0.62)
        }
        .offset(x: w * 0.66, y: top - top * 0.62 + 2)
    }

    private func knob(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(LinearGradient(colors: [Color(hex: 0x6E6862), Color(hex: 0xC9C3BA), Color(hex: 0x8C857D), Color(hex: 0x4E4943)], startPoint: .leading, endPoint: .trailing))
            .overlay {
                HStack(spacing: 1.5) {
                    ForEach(0 ..< Int(width / 3), id: \.self) { _ in Color.black.opacity(0.25).frame(width: 0.75) }
                }
            }
            .clipShape(.rect(cornerRadius: 2))
            .frame(width: width, height: height)
    }

    // MARK: Window and cassette

    /// The recessed bezel and the glass onto the cassette behind it.
    private func cassetteWindow(_ size: CGSize) -> some View {
        let bezel = size.width * 0.035
        let outer = RoundedRectangle(cornerRadius: size.width * 0.06, style: .continuous)
        let inner = RoundedRectangle(cornerRadius: size.width * 0.04, style: .continuous)
        return ZStack {
            outer.fill(LinearGradient(colors: [Color(hex: 0x2A2624), Color(hex: 0x45403B)], startPoint: .top, endPoint: .bottom))
            // Set into the shell: shaded at the top edge, catching light at the bottom.
            outer.strokeBorder(LinearGradient(colors: [.black.opacity(0.45), .white.opacity(0.55)], startPoint: .top, endPoint: .bottom), lineWidth: 1.5)
            cassette(CGSize(width: size.width - bezel * 2, height: size.height - bezel * 2))
                .clipShape(inner)
                .overlay {
                    // The window's depth over the cassette.
                    inner.stroke(.black.opacity(0.7), lineWidth: 5).blur(radius: 4).clipShape(inner)
                }
                .overlay {
                    if contrast != .increased {
                        LinearGradient(
                            stops: [.init(color: .white.opacity(0.14), location: 0), .init(color: .clear, location: 0.35), .init(color: .clear, location: 0.7), .init(color: .white.opacity(0.06), location: 1)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                        .clipShape(inner)
                        .allowsHitTesting(false)
                    }
                }
                .padding(bezel)
        }
        .frame(width: size.width, height: size.height)
    }

    /// The loaded cassette: its paper label with the title between two sprigs, and the reels
    /// through its smoked window.
    private func cassette(_ size: CGSize) -> some View {
        let labelHeight = size.height * (palette.theme == .oak ? 0.36 : 0.34)
        let reelBox = size.height * 0.4
        let reels = TapeReels(throughBook: throughBook, hub: reelBox * 0.32, full: reelBox * 0.62)
        let sprig = Color(hex: 0x6F8A57)
        return VStack(spacing: 0) {
            HStack(spacing: size.width * 0.03) {
                Image(systemName: "leaf")
                    .rotationEffect(.degrees(-35))
                Text(title)
                    .font(.system(size: max(size.height * 0.13, 13), weight: .medium, design: .serif).italic())
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                Image(systemName: "leaf")
                    .scaleEffect(x: -1)
                    .rotationEffect(.degrees(35))
            }
            .font(.system(size: max(size.height * 0.1, 10), weight: .light))
            .foregroundStyle(sprig)
            .padding(.horizontal, size.width * 0.04)
            .frame(maxWidth: .infinity, minHeight: labelHeight, maxHeight: labelHeight)
            .background {
                LinearGradient(colors: [palette.raised, palette.raised.mix(with: palette.shell, by: 0.35)], startPoint: .top, endPoint: .bottom)
                    .overlay { Speckle(density: 8, opacity: 0.05) }
            }
            .clipShape(.rect(bottomLeadingRadius: 2, bottomTrailingRadius: 2))
            .padding(.horizontal, size.width * 0.03)
            .padding(.top, size.height * 0.06)
            TimelineView(.animation(paused: !isPlaying)) { timeline in
                // One turn every 2.4 s at 1×, faster with the speed.
                let angle = Angle.degrees(timeline.date.timeIntervalSinceReferenceDate * 150 * speed)
                ZStack {
                    // The tape running between the reels, seen through the little window.
                    RoundedRectangle(cornerRadius: 2)
                        .fill(LinearGradient(colors: [Color(hex: 0x3B2516), Color(hex: 0x5A3A22), Color(hex: 0x3B2516)], startPoint: .top, endPoint: .bottom))
                        .overlay { RoundedRectangle(cornerRadius: 2).strokeBorder(.white.opacity(0.12), lineWidth: 1) }
                        .frame(width: size.width * 0.2, height: reelBox * 0.5)
                    HStack {
                        Reel(tape: reels.supply, box: reelBox, angle: angle)
                        Spacer(minLength: 0)
                        Reel(tape: reels.takeUp, box: reelBox, angle: angle)
                    }
                    .padding(.horizontal, size.width * 0.17)
                }
            }
            .frame(height: reelBox)
            .padding(.top, size.height * 0.07)
            if palette.theme == .oak, let author {
                Text(author)
                    .font(.system(size: max(size.height * 0.075, 9), design: .serif))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(palette.raised.opacity(0.92), in: .rect(cornerRadius: 2))
                    .padding(.top, size.height * 0.04)
            }
            Spacer(minLength: 0)
        }
        .frame(width: size.width, height: size.height)
        .background(LinearGradient(colors: [Color(hex: 0x2E2621), Color(hex: 0x16110E)], startPoint: .top, endPoint: .bottom))
    }

    /// One reel: the tape wound on it, and the white hub with its teeth, turning.
    private struct Reel: View {
        let tape: Double
        let box: CGFloat
        let angle: Angle

        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color(hex: 0x6E4a32), Color(hex: 0x4A2E1C), Color(hex: 0x2A190F)], center: .center, startRadius: 0, endRadius: tape))
                    .overlay {
                        ForEach([0.92, 0.8, 0.68], id: \.self) { share in
                            Circle().stroke(.black.opacity(0.2), lineWidth: 0.6).frame(width: tape * 2 * share, height: tape * 2 * share)
                        }
                    }
                    .frame(width: tape * 2, height: tape * 2)
                Circle()
                    .fill(LinearGradient(colors: [Color(hex: 0xF6F1E8), Color(hex: 0xCEC6B7)], startPoint: .top, endPoint: .bottom))
                    .overlay { Circle().strokeBorder(.black.opacity(0.25), lineWidth: 0.75) }
                    .frame(width: box * 0.64, height: box * 0.64)
                ZStack {
                    Circle().fill(Color(hex: 0x2A2522)).frame(width: box * 0.34, height: box * 0.34)
                    ForEach(0 ..< 6, id: \.self) { tooth in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color(hex: 0xF0EBE2))
                            .frame(width: box * 0.06, height: box * 0.1)
                            .offset(y: -box * 0.14)
                            .rotationEffect(.degrees(Double(tooth) * 60))
                    }
                }
                .rotationEffect(reduceMotion ? .zero : -angle)
            }
            .frame(width: box, height: box)
        }
    }

    // MARK: Grille and keys

    /// Slots in the plastic over the speaker.
    private func grille(width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(0 ..< 6, id: \.self) { index in
                if index > 0 { Spacer(minLength: 0) }
                Capsule()
                    .fill(palette.shell.mix(with: .black, by: 0.5))
                    .overlay(alignment: .bottom) {
                        Capsule().fill(.white.opacity(0.55)).frame(height: 0.75).offset(y: 1)
                    }
                    .frame(height: max(height * 0.07, 2))
            }
        }
        .frame(width: width, height: height)
    }

    /// Rewind, play and fast forward: chunky keys that move down when pressed. The play key
    /// stays down while the tape runs.
    private func keys(width: CGFloat, height: CGFloat) -> some View {
        let plain = [palette.shell.mix(with: .white, by: 0.45), palette.shell.mix(with: .black, by: 0.04)]
        let main = [palette.accent.mix(with: .white, by: 0.15), palette.accent]
        return HStack(spacing: width * 0.025) {
            Button(action: skipBack) {
                Image(systemName: "backward.fill").foregroundStyle(palette.ink)
            }
            .buttonStyle(ShellKeyStyle(face: plain, edge: palette.shell.mix(with: .black, by: 0.4), isDown: false))
            Button(action: togglePlayback) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill").foregroundStyle(palette.onAccent)
            }
            .buttonStyle(ShellKeyStyle(face: main, edge: palette.accent.mix(with: .black, by: 0.45), isDown: isPlaying))
            .frame(width: width * 0.38)
            Button(action: skipForward) {
                Image(systemName: "forward.fill").foregroundStyle(palette.ink)
            }
            .buttonStyle(ShellKeyStyle(face: plain, edge: palette.shell.mix(with: .black, by: 0.4), isDown: false))
        }
        .font(.system(size: max(height * 0.32, 12), weight: .semibold))
        .frame(width: width, height: height)
        .disabled(!isReady)
    }
}

/// A key on the player's shell: a raised face on a darker edge that disappears as it goes down.
private struct ShellKeyStyle: ButtonStyle {
    let face: [Color]
    let edge: Color
    let isDown: Bool

    func makeBody(configuration: Configuration) -> some View {
        let down = isDown || configuration.isPressed
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        configuration.label
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                shape
                    .fill(LinearGradient(colors: face, startPoint: .top, endPoint: .bottom))
                    .overlay { shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.6), .clear], startPoint: .top, endPoint: .center), lineWidth: 1) }
                    .shadow(color: edge, radius: 0, y: down ? 1 : 4)
                    .shadow(color: .black.opacity(0.25), radius: down ? 1 : 3, y: down ? 1 : 4)
            }
            .offset(y: down ? 3 : 0)
            .contentShape(shape)
            .animation(.snappy(duration: 0.1), value: down)
    }
}
