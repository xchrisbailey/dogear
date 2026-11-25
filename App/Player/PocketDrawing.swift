import DogearCore
import SwiftUI

/// The portable tape player: the theme's photographed shell, with the parts that change drawn
/// over it. The label carries the Book's title; the tape on the reels in the well is how far
/// through the Book the listener is, and the hubs turn while it plays unless Reduce Motion is on.
///
/// Each theme has its own machine. Walnut & Paper's hangs on a leather strap, Oak & Daylight's
/// sits under a carry handle, and Bookcloth & Tape's has a lanyard.
///
/// An illustration only: the working controls are below it, so nothing here is pressable.
struct PocketDrawing: View {
    /// Width over height of the artwork.
    static let ratio: CGFloat = 1.5

    let title: String
    /// 0…1.
    let throughBook: Double
    let isPlaying: Bool
    let speed: Double

    @Environment(\.palette) private var palette

    /// Ink printed on the label, the same on every shell.
    private static let ink = Color(red: 0.18, green: 0.11, blue: 0.07)

    var body: some View {
        let layout = PocketLayout.of(palette.theme)
        GeometryReader { proxy in
            // The artwork fitted into the space, keeping its shape.
            let width = min(proxy.size.width, proxy.size.height * Self.ratio)
            let height = width / Self.ratio
            let hub = width * layout.hub / 2
            let reels = TapeReels(throughBook: throughBook, hub: Double(hub * 1.3), full: Double(width * 0.185))
            let well = CGRect(
                x: layout.well.minX * width, y: layout.well.minY * height,
                width: layout.well.width * width, height: layout.well.height * height
            )
            ZStack {
                Image(layout.art)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: width, height: height)
                    .shadow(color: .black.opacity(0.28), radius: 10, y: 8)
                // Behind the window: the two reels, cut off by its edges.
                ZStack {
                    Reel(tape: CGFloat(reels.supply), hub: hub, isPlaying: isPlaying, speed: speed)
                        .position(x: layout.leftReel * width, y: layout.reelY * height)
                    Reel(tape: CGFloat(reels.takeUp), hub: hub, isPlaying: isPlaying, speed: speed)
                        .position(x: layout.rightReel * width, y: layout.reelY * height)
                    // The label's shadow, and the window's depth at its foot.
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.55), location: 0),
                            .init(color: .clear, location: 0.3),
                            .init(color: .clear, location: 0.8),
                            .init(color: .black.opacity(0.35), location: 1),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(width: well.width, height: well.height)
                    .position(x: well.midX, y: well.midY)
                    // Light on the glass.
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.3),
                            .init(color: .white.opacity(0.07), location: 0.42),
                            .init(color: .clear, location: 0.56),
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    .frame(width: well.width, height: well.height)
                    .position(x: well.midX, y: well.midY)
                }
                .frame(width: width, height: height)
                .mask {
                    RoundedRectangle(cornerRadius: width * 0.006)
                        .frame(width: well.width, height: well.height)
                        .position(x: well.midX, y: well.midY)
                }
                Text(title)
                    .font(.system(size: max(layout.label.height * height * 0.56, 9), weight: .semibold, design: .serif))
                    .foregroundStyle(Self.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .frame(width: layout.label.width * width, height: layout.label.height * height)
                    .position(x: layout.label.midX * width, y: layout.label.midY * height)
            }
            .frame(width: width, height: height)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

/// Where the live parts sit on a shell, as shares of the artwork's width (across) and height
/// (down). Measured from the artwork.
private nonisolated struct PocketLayout {
    let art: String
    /// The box the title is set in, on the paper label.
    let label: CGRect
    let leftReel: CGFloat
    let rightReel: CGFloat
    let reelY: CGFloat
    /// A hub's diameter over the artwork's width.
    let hub: CGFloat
    /// The dark well under the label, where the reels show.
    let well: CGRect

    static func of(_ theme: AppTheme) -> PocketLayout {
        switch theme {
        case .walnut:
            PocketLayout(
                art: "PocketWalnut", label: box(0.507, 0.309, 0.70, 0.112),
                leftReel: 0.31, rightReel: 0.70, reelY: 0.50, hub: 0.117,
                well: CGRect(x: 0.140, y: 0.392, width: 0.735, height: 0.204)
            )
        case .oak:
            PocketLayout(
                art: "PocketOak", label: box(0.50, 0.395, 0.66, 0.095),
                leftReel: 0.32, rightReel: 0.68, reelY: 0.567, hub: 0.105,
                well: CGRect(x: 0.132, y: 0.462, width: 0.732, height: 0.174)
            )
        case .bookcloth:
            PocketLayout(
                art: "PocketBookcloth", label: box(0.53, 0.312, 0.63, 0.115),
                leftReel: 0.35, rightReel: 0.71, reelY: 0.51, hub: 0.115,
                well: CGRect(x: 0.192, y: 0.402, width: 0.678, height: 0.192)
            )
        }
    }

    private static func box(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
        CGRect(x: x - width / 2, y: y - height / 2, width: width, height: height)
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
