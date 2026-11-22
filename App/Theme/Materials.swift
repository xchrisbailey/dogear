import DogearCore
import SwiftUI

/// The physical look shared by the Library, readers and player: wood, brass, paper and the
/// lettering that goes on them. Screens compose these instead of picking their own colors.
enum Theme {
    static let walnutLight = Color(hex: 0x45291A)
    static let walnutDark = Color(hex: 0x2C190E)
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

    /// Nameplates and covers.
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .serif) }
    /// Lettering stamped on spines. Fixed size: a spine is an object, and VoiceOver reads the Book.
    static func stamped(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .serif) }
    /// Notes and shelf labels, scaling with Dynamic Type.
    static func hand(_ size: CGFloat) -> Font { .custom("Noteworthy-Bold", size: size) }
    /// Marker on cassette labels, fixed like spine lettering.
    static func marker(_ size: CGFloat) -> Font { .custom("MarkerFelt-Wide", fixedSize: size) }
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

/// Walnut boards with a faint grain.
struct WoodBackground: View {
    var body: some View {
        LinearGradient(colors: [Theme.walnutLight, Theme.walnutDark], startPoint: .top, endPoint: .bottom)
            .overlay {
                Canvas { context, size in
                    // Evenly spaced hairlines, two rhythms, so it reads as grain and not stripes.
                    for (step, opacity) in [(CGFloat(9), 0.035), (CGFloat(23), 0.16)] {
                        var x = step / 2
                        while x < size.width {
                            let line = Path(CGRect(x: x, y: 0, width: 1, height: size.height))
                            context.fill(line, with: .color(opacity > 0.1 ? .black.opacity(opacity) : .white.opacity(opacity)))
                            x += step
                        }
                    }
                }
            }
            .ignoresSafeArea()
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

/// A handwritten card in a brass holder, naming a shelf.
struct ShelfLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(Theme.hand(14))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 1)
            .background(Theme.paper, in: .rect(cornerRadius: 2))
            .padding(4)
            .background(LinearGradient(colors: [Theme.brass[1], Theme.brass[2]], startPoint: .top, endPoint: .bottom), in: .rect(cornerRadius: 3))
            .shadow(color: .black.opacity(0.6), radius: 1, y: 1)
            .accessibilityAddTraits(.isHeader)
    }
}

/// An engraved brass plate with a screw at each end.
struct Nameplate: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack {
            Screw()
            VStack(spacing: 2) {
                Text(title)
                    .font(Theme.display(28))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(subtitle.uppercased())
                    .font(Theme.stamped(11))
                    .tracking(2)
                    .opacity(0.8)
            }
            .foregroundStyle(Theme.engraved)
            .frame(maxWidth: .infinity)
            Screw()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(LinearGradient(colors: Theme.brass, startPoint: .top, endPoint: .bottom), in: .rect(cornerRadius: 6))
        .shadow(color: .black.opacity(0.55), radius: 4, y: 3)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private struct Screw: View {
        var body: some View {
            Circle()
                .fill(RadialGradient(colors: [.white, Theme.brass[2], Theme.engraved], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 5))
                .frame(width: 8, height: 8)
                .overlay { Rectangle().fill(.black.opacity(0.5)).frame(width: 6, height: 1).rotationEffect(.degrees(35)) }
                .accessibilityHidden(true)
        }
    }
}

/// A brass drawer front that sits pressed in while it's the one chosen.
struct DrawerButtonStyle: ButtonStyle {
    let isOn: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed = isOn || configuration.isPressed
        configuration.label
            .font(Theme.hand(15))
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background {
                // The drop is the drawer front's own, so the lettering isn't doubled by it.
                RoundedRectangle(cornerRadius: 4)
                    .fill(LinearGradient(
                        colors: pressed ? [Theme.brass[1], Theme.brass[0]] : [Theme.brass[0], Theme.brass[2]],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .shadow(color: .black.opacity(pressed ? 0 : 0.5), radius: 0, y: pressed ? 0 : 3)
            }
            .overlay {
                if pressed {
                    RoundedRectangle(cornerRadius: 4).strokeBorder(.black.opacity(0.35), lineWidth: 1)
                }
            }
            .offset(y: pressed ? 3 : 0)
    }
}

/// A paper tag hung from the shelf by a brass grommet, for notices.
struct PaperTag<Content: View>: View {
    var edge: Color = Theme.inkSoft
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Theme.backPanel)
                .frame(width: 9, height: 9)
                .overlay { Circle().stroke(Theme.brass[1], lineWidth: 2) }
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
