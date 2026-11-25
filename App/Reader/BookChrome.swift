import DogearCore
@preconcurrency import ReadiumNavigator
import SwiftUI

/// The paper a Book is printed on, by reading theme.
struct ReaderPaper {
    let paper: UInt32
    let ink: UInt32
    /// The two tones of the stacked page edges.
    let edges: (UInt32, UInt32)

    init(_ theme: ReadiumNavigator.Theme) {
        switch theme {
        case .light:
            paper = 0xF6EFDC
            ink = 0x2A2118
            edges = (0xCFC3A4, 0xF1E8D0)
        case .sepia:
            paper = 0xECD9B4
            ink = 0x3B2A17
            edges = (0xBFA878, 0xE4CFA6)
        case .dark:
            paper = 0x1D1A17
            ink = 0xD9CFBB
            edges = (0x0F0D0B, 0x2A2622)
        }
    }
}

extension EPUBPreferences {
    /// These preferences printed on the theme's paper. Only Readium is told: the colors aren't
    /// the reader's choice, so they aren't saved with it.
    var onPaper: EPUBPreferences {
        let paper = ReaderPaper(theme ?? .light)
        var preferences = self
        preferences.backgroundColor = ReadiumNavigator.Color(rawValue: Int(paper.paper))
        preferences.textColor = ReadiumNavigator.Color(rawValue: Int(paper.ink))
        return preferences
    }
}

extension PDFPreferences {
    /// A PDF's pages lie straight on the desk, in place of PDFKit's grey.
    static var onDesk: PDFPreferences {
        PDFPreferences(backgroundColor: ReadiumNavigator.Color(uiColor: UIColor(Theme.desk[1])))
    }
}

/// The dark desk an open Book lies on.
struct Desk: View {
    var body: some View {
        Rectangle()
            .fill(RadialGradient(colors: Theme.desk, center: UnitPoint(x: 0.5, y: 0.4), startRadius: 0, endRadius: 700))
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

/// A page lying in an open Book: cover board behind, the gutter's shadow by the spine, the
/// other pages stacked at the outer edge and a ribbon over the top.
struct OpenBook<Page: View>: View {
    let paper: ReaderPaper
    /// A scrolling Book has no stack of pages to show.
    let showsPageEdges: Bool
    /// Two pages side by side meet at the spine; one page has it at its inner edge.
    let spineInMiddle: Bool
    @ViewBuilder var page: Page

    /// The shadow where the paper dips into the spine. Between two pages it is only a faint
    /// crease, so the eye isn't pulled to the middle of the spread while reading.
    private var gutter: [Gradient.Stop] {
        spineInMiddle
            ? [
                .init(color: .clear, location: 0.475), .init(color: .black.opacity(0.025), location: 0.49),
                .init(color: .black.opacity(0.07), location: 0.5),
                .init(color: .black.opacity(0.025), location: 0.51), .init(color: .clear, location: 0.525),
            ]
            : [.init(color: .black.opacity(0.3), location: 0), .init(color: .black.opacity(0.08), location: 0.06), .init(color: .clear, location: 0.16)]
    }

    var body: some View {
        page
            .background(SwiftUI.Color(hex: paper.paper))
            .overlay {
                LinearGradient(stops: gutter, startPoint: .leading, endPoint: .trailing)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .padding(.trailing, showsPageEdges ? PageEdges.width : 0)
            .background(alignment: .trailing) {
                if showsPageEdges { PageEdges(paper: paper) }
            }
            .padding(.vertical, 5)
            .padding(.trailing, 8)
            .background {
                UnevenRoundedRectangle(bottomTrailingRadius: 10, topTrailingRadius: 10)
                    .fill(Theme.coverBoard)
                    .overlay { UnevenRoundedRectangle(bottomTrailingRadius: 10, topTrailingRadius: 10).strokeBorder(.white.opacity(0.08)) }
                    .shadow(color: .black.opacity(0.7), radius: 14, y: 8)
            }
            .overlay(alignment: .topTrailing) {
                Ribbon()
                    .fill(LinearGradient(colors: [Theme.ribbonDark, Theme.ribbon, Theme.ribbonDark], startPoint: .leading, endPoint: .trailing))
                    .frame(width: 14, height: 62)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 2)
                    .padding(.trailing, 54)
                    .offset(y: -6)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 6)
            .padding(.trailing, 8)
    }
}

/// The edges of the pages still to read, seen side on.
private struct PageEdges: View {
    static let width: CGFloat = 9
    let paper: ReaderPaper

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(SwiftUI.Color(hex: paper.edges.1)))
            var x: CGFloat = 0
            while x < size.width {
                context.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(SwiftUI.Color(hex: paper.edges.0)))
                x += 3
            }
        }
        .frame(width: Self.width)
        .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: 3, topTrailingRadius: 3))
        .accessibilityHidden(true)
    }
}

/// The readers' top bar, on a solid strip of the app theme's canvas so it reads over any page.
struct ReaderBar<Actions: View>: View {
    let title: String
    let close: () -> Void
    @ViewBuilder var actions: Actions

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 0) {
            Button("Close", systemImage: "xmark", action: close)
            Spacer()
            actions
        }
        .buttonStyle(ReaderBarButtonStyle())
        .labelStyle(.iconOnly)
        .padding(.horizontal, 8)
        .frame(height: 52)
        .background {
            Text(title)
                .font(.system(.headline, design: .serif, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(palette.text)
                .padding(.horizontal, 104)
                .accessibilityAddTraits(.isHeader)
        }
        .background {
            palette.canvas
                .overlay(alignment: .bottom) { palette.outline.frame(height: 1) }
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                .ignoresSafeArea(edges: .top)
        }
        .environment(\.colorScheme, palette.scheme)
    }
}

private struct ReaderBarButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.palette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(palette.canvasAction)
            .opacity(!isEnabled ? 0.35 : configuration.isPressed ? 0.6 : 1)
            .frame(width: 44, height: 44)
            .contentShape(.rect)
    }
}

/// A note slipped between the pages, for a problem that doesn't stop the reading.
struct PaperSlip: View {
    let text: String
    let dismiss: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: dismiss) {
            Label(text, systemImage: "wifi.exclamationmark")
                .font(Theme.label(.subheadline))
                .foregroundStyle(palette.ink)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.raised, in: .rect(cornerRadius: 8))
                .shadow(color: .black.opacity(0.5), radius: 4, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Dismisses this note")
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }
}
