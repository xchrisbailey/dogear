import DogearCore
import SwiftUI

/// Materials that look the same in every app theme: the ribbon in a Book, the wrapping on one Dogear
/// can't open, cassette tape, and the desk an open Book lies on. Everything that changes with the
/// theme is in ``Palette``.
enum Theme {
    static let ribbon = Color(hex: 0xB3262E)
    static let ribbonDark = Color(hex: 0x8C1C1C)
    static let kraft = SpineColor(red: 0.655, green: 0.510, blue: 0.353)
    /// A Download running.
    static let glow = Color(hex: 0x8EF0C1)
    static let tape = Color(hex: 0x4A2E1C)
    /// The dark window of a cassette or player.
    static let window = [Color(hex: 0x2A211B), Color(hex: 0x120D0A)]
    /// The desk an open Book lies on, lit from above its middle.
    static let desk = [Color(hex: 0x3A2314), Color(hex: 0x170D07)]
    static let coverBoard = Color(hex: 0x5A1418)
    /// A knot of cream thread, from light top to shaded foot.
    static let thread = [Color(hex: 0xF4EAD2), Color(hex: 0xE6C8A0), Color(hex: 0x8A6E4E)]

    /// Lettering stamped on spines and cassette labels. Fixed size: a spine is an object, and
    /// VoiceOver reads the Book.
    static func stamped(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold, design: .serif) }
    /// Notes and small labels: the system sans, scaling with Dynamic Type.
    static func label(_ style: Font.TextStyle) -> Font { .system(style, weight: .semibold) }
}

/// The app theme's colors, by role. Screens read it from the environment, so changing the theme
/// in Settings redraws everything at once without reloading a Book or the player.
nonisolated struct Palette: Equatable, Sendable {
    let theme: AppTheme
    /// Behind everything, including the navigation bar.
    let canvas: Color
    /// Paper raised off the canvas: cards, labels, the search field, the cassette label.
    let raised: Color
    /// Text straight on the canvas.
    let text: Color
    let textSecondary: Color
    /// Text on paper, whatever the theme.
    let ink: Color
    let inkSecondary: Color
    /// The filled control and progress, and what sits on that fill.
    let accent: Color
    let onAccent: Color
    let shelfBacking: Color
    let ledgeTop: Color
    let ledgeFace: Color
    /// Decorative edges.
    let outline: Color
    /// Edges a control needs to be seen: 3:1 against the canvas.
    let boundary: Color
    let shell: Color
    let shellTrim: Color
    /// A lighter wash over the top of the canvas, for daylight.
    let canvasLight: Color?

    /// Lettering of a small action straight on the canvas. Rust on bottle green is too dark for
    /// small text, so Bookcloth letters those in cream.
    var canvasAction: Color { theme == .bookcloth ? text : accent }
    /// Lettering of an action on paper: dark ink in Bookcloth, where rust is for fills.
    var paperAction: Color { theme == .bookcloth ? ink : accent }
    /// The appearance the canvas reads as, for system controls and the status bar.
    var scheme: ColorScheme { theme.hasDarkCanvas ? .dark : .light }
    /// Whether the shelves are dark wood, so text straight on them is light.
    var hasDarkShelves: Bool { theme != .oak }

    init(_ theme: AppTheme) {
        self.theme = theme
        switch theme {
        case .walnut:
            canvas = Color(hex: 0xF4E8D7)
            raised = Color(hex: 0xFFF4E3)
            text = Color(hex: 0x2F1C13)
            textSecondary = Color(hex: 0x655045)
            ink = Color(hex: 0x2F1C13)
            inkSecondary = Color(hex: 0x655045)
            accent = Color(hex: 0x673922)
            onAccent = Color(hex: 0xFFF4E3)
            shelfBacking = Color(hex: 0x54321F)
            ledgeTop = Color(hex: 0x9F673E)
            ledgeFace = Color(hex: 0x633A24)
            outline = Color(hex: 0xBDA891)
            boundary = Color(hex: 0x8C735F)
            shell = Color(hex: 0xE8D0AB)
            shellTrim = Color(hex: 0x513426)
            canvasLight = nil
        case .oak:
            canvas = Color(hex: 0xF5EFE5)
            raised = Color(hex: 0xFFFAF1)
            text = Color(hex: 0x292F21)
            textSecondary = Color(hex: 0x535C4C)
            ink = Color(hex: 0x292F21)
            inkSecondary = Color(hex: 0x535C4C)
            accent = Color(hex: 0x4E644A)
            onAccent = Color(hex: 0xFFFAF1)
            shelfBacking = Color(hex: 0xE7D6B8)
            ledgeTop = Color(hex: 0xDEAB70)
            ledgeFace = Color(hex: 0xAB713F)
            outline = Color(hex: 0xBDB4A6)
            boundary = Color(hex: 0x807664)
            shell = Color(hex: 0xEEE1C7)
            shellTrim = Color(hex: 0x526749)
            canvasLight = Color(hex: 0xFBF8F2)
        case .bookcloth:
            canvas = Color(hex: 0x103B31)
            raised = Color(hex: 0xF3E4C9)
            text = Color(hex: 0xFFF3DF)
            textSecondary = Color(hex: 0xD2DFD2)
            ink = Color(hex: 0x17352A)
            inkSecondary = Color(hex: 0x455A4E)
            accent = Color(hex: 0xD45F35)
            onAccent = Color(hex: 0x18120F)
            shelfBacking = Color(hex: 0x123D33)
            ledgeTop = Color(hex: 0x9C623D)
            ledgeFace = Color(hex: 0x633B29)
            outline = Color(hex: 0x62887A)
            boundary = Color(hex: 0x799C8F)
            shell = Color(hex: 0xE8D7B7)
            shellTrim = Color(hex: 0x26463B)
            canvasLight = nil
        }
    }
}

private nonisolated struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette(.standard)
}

nonisolated extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

/// The app theme saved on this device.
enum AppearancePreferences {
    /// Read through `@AppStorage` at the root and in Settings, so a change shows at once.
    static let themeKey = "app.theme"
}

extension View {
    /// Draws everything under it in `theme`: its palette, and light or dark system controls and
    /// status bar to match the canvas.
    func appTheme(_ theme: AppTheme) -> some View {
        let palette = Palette(theme)
        return environment(\.palette, palette)
            .preferredColorScheme(palette.scheme)
            .tint(palette.canvasAction)
    }

    /// A serif title that grows with Dynamic Type from `size` at the default text size.
    func serifTitle(_ size: CGFloat, relativeTo style: Font.TextStyle) -> some View {
        modifier(SerifTitle(size: size, style: style))
    }
}

private struct SerifTitle: ViewModifier {
    @ScaledMetric private var size: CGFloat

    init(size: CGFloat, style: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: .semibold, design: .serif))
    }
}

nonisolated extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255
        )
    }

    init(_ color: SpineColor) {
        self.init(red: color.red, green: color.green, blue: color.blue)
    }
}

/// The theme's canvas under a screen: paper with a faint grain, oat paper in daylight, or green
/// linen. Texture stays faint, and goes with Increase Contrast.
struct CanvasBackground: View {
    @Environment(\.palette) private var palette
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        palette.canvas
            .overlay {
                if let light = palette.canvasLight {
                    // Daylight from the top leading corner.
                    LinearGradient(colors: [light, light.opacity(0)], startPoint: .topLeading, endPoint: .center)
                }
            }
            .overlay {
                if contrast != .increased {
                    if palette.theme == .bookcloth { Linen(opacity: 0.05) } else { Speckle(opacity: 0.035) }
                }
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

/// Speckle from paper fibres or cloth, light and dark. Seeded, so it doesn't shimmer when the
/// view redraws. `density` is square points per speck.
struct Speckle: View {
    var density: CGFloat = 60
    let opacity: Double

    var body: some View {
        Canvas { context, size in
            var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
            func next() -> CGFloat {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return CGFloat(seed >> 33) / CGFloat(UInt32.max >> 1)
            }
            let count = Int(size.width * size.height / density)
            for _ in 0 ..< count {
                let dot = Path(CGRect(x: next() * size.width, y: next() * size.height, width: 1, height: 1))
                let light = next() > 0.55
                context.fill(dot, with: .color(light ? .white.opacity(opacity) : .black.opacity(opacity * 1.5)))
            }
        }
        .drawingGroup()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The weave of book cloth: fine light weft over darker warp, too small to read as stripes.
struct Linen: View {
    let opacity: Double

    var body: some View {
        Canvas { context, size in
            var y: CGFloat = 0
            while y < size.height {
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.white.opacity(opacity)))
                y += 3
            }
            var x: CGFloat = 0
            while x < size.width {
                context.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(.black.opacity(opacity * 2)))
                x += 3
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Long streaks of grain running along a board.
struct WoodGrain: View {
    let opacity: Double
    var vertical = false

    var body: some View {
        Canvas { context, size in
            var seed: UInt64 = 0xD1B5_4A32_D192_ED03
            func next() -> CGFloat {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return CGFloat(seed >> 33) / CGFloat(UInt32.max >> 1)
            }
            let across = vertical ? size.width : size.height
            let along = vertical ? size.height : size.width
            var offset: CGFloat = 0
            while offset < across {
                let width = 0.5 + next() * 2.5
                let dark = next() > 0.35
                let start = next() * along * 0.3
                let rect = vertical
                    ? CGRect(x: offset, y: start, width: width, height: along)
                    : CGRect(x: start, y: offset, width: along, height: width)
                context.fill(Path(rect), with: .color(dark ? .black.opacity(opacity) : .white.opacity(opacity * 0.6)))
                offset += 3 + next() * 7
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The back of the bookcase behind a row, in the theme's wood or cloth: lit warm from above
/// the middle, falling into shade at the sides and under the shelf above, between two uprights.
struct ShelfBacking: View {
    @Environment(\.palette) private var palette
    @Environment(\.colorSchemeContrast) private var contrast

    private var isCloth: Bool { palette.theme == .bookcloth }
    /// Light wood shows shade less.
    private var shade: Double { palette.hasDarkShelves ? 1 : 0.45 }

    var body: some View {
        palette.shelfBacking
            .overlay {
                if contrast != .increased {
                    if isCloth { Linen(opacity: 0.05) } else { WoodGrain(opacity: palette.hasDarkShelves ? 0.06 : 0.025, vertical: true).blur(radius: 0.5) }
                }
            }
            // Lamplight on the middle of the case.
            .overlay {
                RadialGradient(colors: [Color(hex: 0xFFE2B0).opacity(palette.hasDarkShelves ? 0.12 : 0.18), .clear], center: UnitPoint(x: 0.5, y: 0.2), startRadius: 0, endRadius: 320)
            }
            // The sides of the case in shade.
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.26 * shade), location: 0),
                        .init(color: .clear, location: 0.16),
                        .init(color: .clear, location: 0.84),
                        .init(color: .black.opacity(0.26 * shade), location: 1),
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
            }
            // Shade cast by the shelf above.
            .overlay(alignment: .top) {
                LinearGradient(colors: [.black.opacity(0.42 * shade), .black.opacity(0.1 * shade), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 30)
            }
            .overlay(alignment: .leading) { if !isCloth { Upright(leading: true) } }
            .overlay(alignment: .trailing) { if !isCloth { Upright(leading: false) } }
            .accessibilityHidden(true)
    }

    /// A side of the bookcase, seen edge-on.
    private struct Upright: View {
        let leading: Bool

        @Environment(\.palette) private var palette

        var body: some View {
            LinearGradient(
                colors: leading ? [palette.ledgeTop, palette.ledgeFace] : [palette.ledgeFace, palette.ledgeTop.mix(with: palette.ledgeFace, by: 0.5)],
                startPoint: .leading, endPoint: .trailing
            )
            .overlay { WoodGrain(opacity: 0.1, vertical: true) }
            .frame(width: 7)
            .shadow(color: .black.opacity(0.35), radius: 3, x: leading ? 2 : -2)
        }
    }
}

/// The front edge of a shelf: its lit top with a bright lip, and its face in shade, casting a
/// shadow on the back of the shelf below.
struct ShelfLedge: View {
    @Environment(\.palette) private var palette
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [palette.ledgeTop.mix(with: palette.ledgeFace, by: 0.25), palette.ledgeTop], startPoint: .top, endPoint: .bottom)
                .frame(height: 5)
            Color.white.opacity(0.28).frame(height: 1)
            LinearGradient(colors: [palette.ledgeFace.mix(with: palette.ledgeTop, by: 0.3), palette.ledgeFace, palette.ledgeFace.mix(with: .black, by: 0.2)], startPoint: .top, endPoint: .bottom)
                .frame(height: 12)
        }
        .overlay {
            if contrast != .increased { WoodGrain(opacity: 0.12) }
        }
        .shadow(color: .black.opacity(palette.hasDarkShelves ? 0.5 : 0.22), radius: 4, y: 4)
        .zIndex(1)
        .accessibilityHidden(true)
    }
}

/// A paper card raised off the canvas.
struct PaperCard: ViewModifier {
    var radius: CGFloat = 14

    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content
            .foregroundStyle(palette.ink)
            .background(palette.raised, in: .rect(cornerRadius: radius))
            .overlay { RoundedRectangle(cornerRadius: radius).strokeBorder(palette.outline.opacity(0.6), lineWidth: 1) }
            .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
            // Paper is light in every theme, so system text and controls on it are too.
            .environment(\.colorScheme, .light)
            .tint(palette.paperAction)
    }
}

extension View {
    func paperCard(radius: CGFloat = 14) -> some View {
        modifier(PaperCard(radius: radius))
    }
}

/// The highest-priority action: the accent fill.
struct FilledActionStyle: ButtonStyle {
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(palette.onAccent)
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 16)
            .background(palette.accent, in: .rect(cornerRadius: 12))
            .opacity(!isEnabled ? 0.45 : configuration.isPressed ? 0.8 : 1)
    }
}

/// Any other action: an outline in the strong control boundary, lettered like the canvas, or
/// like paper when `onPaper`.
struct OutlinedActionStyle: ButtonStyle {
    var onPaper = false
    var fillsWidth = true

    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(onPaper ? palette.ink : palette.text)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: 44)
            .background {
                Capsule()
                    .fill(configuration.isPressed ? (onPaper ? palette.ink : palette.text).opacity(0.08) : .clear)
                Capsule().strokeBorder(onPaper ? palette.inkSecondary : palette.boundary, lineWidth: 1)
            }
            .contentShape(.capsule)
            .opacity(isEnabled ? 1 : 0.45)
    }
}

/// A row of segments for choosing one of a few. The chosen one is filled with the accent.
struct Segments<Value: Hashable>: View {
    @Binding var selection: Value
    let choices: [(name: String, value: Value)]
    /// On a paper card rather than the canvas.
    var onPaper = false

    @Environment(\.palette) private var palette

    var body: some View {
        let line = onPaper ? palette.inkSecondary : palette.boundary
        HStack(spacing: 0) {
            ForEach(Array(choices.enumerated()), id: \.offset) { index, choice in
                let isOn = choice.value == selection
                if index > 0 {
                    line.opacity(isOn || choices[index - 1].value == selection ? 0 : 0.6)
                        .frame(width: 1, height: 22)
                }
                Button { selection = choice.value } label: {
                    Text(choice.name)
                        .font(.subheadline.weight(isOn ? .semibold : .regular))
                        .foregroundStyle(isOn ? palette.onAccent : onPaper ? palette.ink : palette.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background { if isOn { Capsule().fill(palette.accent) } }
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(.horizontal, 3)
        .background { Capsule().strokeBorder(line, lineWidth: 1).padding(.vertical, 2) }
        .animation(.snappy(duration: 0.15), value: selection)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// A paper tag for notices, its left edge colored by what kind of notice it is.
struct PaperTag<Content: View>: View {
    var edge: Color?
    @ViewBuilder var content: Content

    @Environment(\.palette) private var palette

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .padding(.leading, 4)
            .background(palette.raised)
            .overlay(alignment: .leading) { (edge ?? palette.inkSecondary).frame(width: 4) }
            .clipShape(.rect(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(palette.outline.opacity(0.6), lineWidth: 1) }
            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
            // Paper is light whatever the theme, so its text is always ink.
            .environment(\.colorScheme, .light)
    }
}

/// A Book's cover, or a plain title-led stand-in when it has none or it hasn't loaded.
struct CoverImage: View {
    let cover: Cover?
    let title: String
    let library: Library

    @State private var image: UIImage?
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(.rect(cornerRadius: 4))
            } else {
                // No cover: a plain cloth binding in the theme's accent, its title stamped on it.
                RoundedRectangle(cornerRadius: 4)
                    .fill(LinearGradient(
                        colors: [palette.accent.mix(with: .white, by: 0.08), palette.accent.mix(with: .black, by: 0.12)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .overlay(alignment: .leading) {
                        // The joint beside the spine.
                        LinearGradient(colors: [.black.opacity(0.25), .white.opacity(0.12), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 9)
                    }
                    .overlay { RoundedRectangle(cornerRadius: 2).strokeBorder(palette.onAccent.opacity(0.45), lineWidth: 0.75).padding(6) }
                    .overlay {
                        Text(title)
                            .font(Theme.stamped(14))
                            .foregroundStyle(palette.onAccent)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.6)
                            .padding(12)
                    }
                    .clipShape(.rect(cornerRadius: 4))
                    .aspectRatio(2 / 3, contentMode: .fit)
            }
        }
        .task(id: cover) {
            guard let cover, let data = await library.image(for: cover) else { return }
            image = UIImage(data: data)
        }
    }
}
