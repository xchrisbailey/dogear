import DogearCore
import SwiftUI

/// The physical look shared by the Library, readers and player: wood, felt, brass, cloth, leather, paper and the
/// lettering that goes on them. Screens compose these instead of picking their own colors.
enum Theme {
    /// The felt lining behind the bookcase.
    static let felt = [Color(hex: 0x2F2A26), Color(hex: 0x211D1A)]
    /// The back of the bookcase, behind the spines.
    static let backPanel = Color(hex: 0x1F120A)
    static let ledge = [Color(hex: 0x8A5A36), Color(hex: 0x6B4126), Color(hex: 0x4A2B18)]
    static let brass = [Color(hex: 0xF3DC9A), Color(hex: 0xC9A04F), Color(hex: 0x9C7428), Color(hex: 0xD8B467)]
    /// Engraved text on brass.
    static let engraved = Color(hex: 0x3A2610)
    /// Gold lettering on wood.
    static let gilt = Color(hex: 0xE8C77A)
    static let paper = Color(hex: 0xF4EAD2)
    static let ink = Color(hex: 0x3B2A1A)
    static let inkSoft = Color(hex: 0x5B4A36)
    /// Handwriting on labels.
    static let pen = Color(hex: 0x1D2B4F)
    static let ribbon = Color(hex: 0xB3262E)
    static let kraft = SpineColor(red: 0.655, green: 0.510, blue: 0.353)
    static let glow = Color(hex: 0x8EF0C1)
    static let cassetteShell = [Color(hex: 0x2B2B2E), Color(hex: 0x18181A)]
    static let tape = Color(hex: 0x4A2E1C)
    /// The desk an open Book lies on, lit from above its middle.
    static let desk = [Color(hex: 0x3A2314), Color(hex: 0x170D07)]
    static let coverBoard = Color(hex: 0x5A1418)
    static let leather = [Color(hex: 0x3D0E12), Color(hex: 0x5A1418)]
    /// Gold foil stamped into leather.
    static let foil = Color(hex: 0xF1D38A)
    static let ribbonDark = Color(hex: 0x8C1C1C)
    /// Green linen book cloth, lit from above its middle, for the Library's title board.
    static let bookCloth = [Color(hex: 0x3E5C49), Color(hex: 0x2B4234), Color(hex: 0x243729)]
    /// Lettering pressed into book cloth without foil: a shade darker than the cloth.
    static let debossed = Color(hex: 0x172820)
    /// Tan leather tabs, and the darker one pushed into its tray.
    static let tabLeather = [Color(hex: 0x6A4630), Color(hex: 0x553621)]
    static let tabLeatherPressed = [Color(hex: 0x3A2416), Color(hex: 0x4A2E1C)]
    static let tabLettering = Color(hex: 0xC9AE88)
    static let tabLetteringPressed = Color(hex: 0xF1E3C8)
    static let stitching = Color(hex: 0xE6C8A0)
    static let tabTray = Color(hex: 0x24140B)
    /// Controls and marks on the Library that aren't lettering: the tan of the tab lettering.
    static let accent = tabLettering
    /// Dark iron, for eyelets.
    static let iron = Color(hex: 0x5A5652)
    /// A knot of cream thread, from light top to shaded foot.
    static let thread = [Color(hex: 0xF4EAD2), Color(hex: 0xE6C8A0), Color(hex: 0x8A6E4E)]

    /// Nameplates and covers.
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .serif) }
    /// Lettering stamped on spines. Fixed size: a spine is an object, and VoiceOver reads the Book.
    static func stamped(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .serif) }
    /// Shelf labels, drawer buttons and notes: the system sans, scaling with Dynamic Type.
    static func label(_ style: Font.TextStyle) -> Font { .system(style, weight: .semibold) }
    /// Titles on a cassette face, fixed like spine lettering.
    static func cassetteLabel(_ size: CGFloat) -> Font { .system(size: size, weight: .bold) }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255
        )
    }

    init(_ color: SpineColor) {
        self.init(red: color.red, green: color.green, blue: color.blue)
    }
}

/// Warm charcoal wool behind the shelves, like a drawer lining: quiet, so the Books carry the color.
struct FeltBackground: View {
    var body: some View {
        LinearGradient(colors: Theme.felt, startPoint: .top, endPoint: .bottom)
            // Light pooled at the top, falling off toward the edges.
            .overlay {
                RadialGradient(colors: [.white.opacity(0.05), .clear], center: .top, startRadius: 0, endRadius: 420)
            }
            .overlay {
                EllipticalGradient(colors: [.clear, .black.opacity(0.35)], center: .center, startRadiusFraction: 0.35, endRadiusFraction: 0.75)
            }
            .overlay { Fibers() }
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }

    /// Speckle from the wool. Seeded, so it doesn't shimmer when the view redraws.
    private struct Fibers: View {
        var body: some View {
            Canvas { context, size in
                var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
                func next() -> CGFloat {
                    seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                    return CGFloat(seed >> 33) / CGFloat(UInt32.max >> 1)
                }
                let count = Int(size.width * size.height / 40)
                for _ in 0..<count {
                    let dot = Path(CGRect(x: next() * size.width, y: next() * size.height, width: 1, height: 1))
                    let light = next() > 0.5
                    context.fill(dot, with: .color(light ? .white.opacity(0.04) : .black.opacity(0.18)))
                }
            }
            .drawingGroup()
        }
    }
}

/// The front edge of a shelf, under a row of Books.
struct ShelfLedge: View {
    var body: some View {
        LinearGradient(colors: Theme.ledge, startPoint: .top, endPoint: .bottom)
            .frame(height: 16)
            .overlay(alignment: .top) { Color.white.opacity(0.25).frame(height: 1) }
            .clipShape(.rect(cornerRadius: 2))
            .shadow(color: .black.opacity(0.55), radius: 8, y: 8)
            .accessibilityHidden(true)
    }
}

/// A stitched leather tag naming a shelf, lettered like the tabs above it but smaller and in capitals.
struct ShelfLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(Theme.stamped(12))
            .tracking(2)
            .foregroundStyle(Theme.tabLettering)
            .shadow(color: .black.opacity(0.5), radius: 0, y: -1)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 4)
                    .fill(LinearGradient(colors: Theme.tabLeather, startPoint: .top, endPoint: .bottom))
                    .overlay(alignment: .top) { Color.white.opacity(0.1).frame(height: 1).clipShape(.rect(cornerRadius: 4)) }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(Theme.stitching.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .padding(3)
                    .accessibilityHidden(true)
            }
            .shadow(color: .black.opacity(0.5), radius: 2, y: 2)
            .accessibilityLabel(text)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A board covered in linen book cloth, its title blind-stamped: pressed in, no foil.
struct ClothBoard: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 3) {
            Text(title)
                .font(Theme.display(28))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(subtitle.uppercased())
                .font(Theme.stamped(11))
                .tracking(2.5)
        }
        .foregroundStyle(Theme.debossed)
        // Pressed in: lit along the lower edge of each letter, shadowed along the upper.
        .shadow(color: .white.opacity(0.2), radius: 0, y: 1)
        .shadow(color: .black.opacity(0.5), radius: 0.5, y: -1)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background {
            RadialGradient(colors: Theme.bookCloth, center: .top, startRadius: 0, endRadius: 260)
                .overlay { Linen() }
                .overlay {
                    // The blind-stamped border, inset from the board's edge.
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(.black.opacity(0.35), lineWidth: 1)
                        .shadow(color: .white.opacity(0.09), radius: 0, y: 1)
                        .padding(9)
                }
                .overlay(alignment: .top) { Color.white.opacity(0.12).frame(height: 1) }
                .clipShape(.rect(cornerRadius: 5))
        }
        .shadow(color: .black.opacity(0.55), radius: 5, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// The weave: fine light weft over darker warp, too small to read as stripes.
    private struct Linen: View {
        var body: some View {
            Canvas { context, size in
                var y: CGFloat = 0
                while y < size.height {
                    context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.white.opacity(0.045)))
                    y += 3
                }
                var x: CGFloat = 0
                while x < size.width {
                    context.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(.black.opacity(0.12)))
                    x += 3
                }
            }
            .accessibilityHidden(true)
        }
    }
}

/// A row of stitched leather tabs set in a dark tray, for choosing one of a few.
struct LeatherTabs<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 4) { content }
            .padding(4)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Theme.tabTray.shadow(.inner(color: .black.opacity(0.6), radius: 3, y: 2)))
                    .shadow(color: .white.opacity(0.08), radius: 0, y: 1)
            }
    }
}

/// A leather tab in a ``LeatherTabs`` tray that sinks in while it's the one chosen.
struct LeatherTabStyle: ButtonStyle {
    let isOn: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed = isOn || configuration.isPressed
        configuration.label
            .font(Theme.label(.subheadline))
            .foregroundStyle(pressed ? Theme.tabLetteringPressed : Theme.tabLettering)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background {
                let shape = RoundedRectangle(cornerRadius: 4)
                shape
                    .fill(
                        LinearGradient(colors: pressed ? Theme.tabLeatherPressed : Theme.tabLeather, startPoint: .top, endPoint: .bottom)
                            .shadow(.inner(color: .black.opacity(pressed ? 0.65 : 0), radius: 3, y: 3))
                    )
                    .overlay(alignment: .top) {
                        if !pressed { Color.white.opacity(0.12).frame(height: 1).clipShape(shape) }
                    }
                    .shadow(color: .black.opacity(pressed ? 0 : 0.4), radius: 1, y: 2)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(Theme.stitching.opacity(pressed ? 0.2 : 0.28), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .padding(4)
                    .accessibilityHidden(true)
            }
    }
}

/// A paper tag hung from the shelf by an iron eyelet, for notices.
struct PaperTag<Content: View>: View {
    var edge: Color = Theme.inkSoft
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Theme.backPanel)
                .frame(width: 9, height: 9)
                .overlay { Circle().stroke(Theme.iron, lineWidth: 2) }
                .accessibilityHidden(true)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Theme.paper)
        .overlay(alignment: .leading) { edge.frame(width: 4) }
        .clipShape(.rect(cornerRadius: 3))
        .shadow(color: .black.opacity(0.5), radius: 5, y: 4)
        // Paper is light whatever the device's appearance, so its text is always ink.
        .environment(\.colorScheme, .light)
    }
}
