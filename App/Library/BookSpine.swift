import DogearCore
import SwiftUI

/// What a spine or cassette case shows about a Book's Downloads.
enum ShelfDownload: Equatable {
    case none
    case downloading(Double)
    case failed
    case downloaded

    /// From the states of a Book's Downloads. Downloading wins over failed, which wins over
    /// downloaded, so the busiest state shows.
    init(_ states: [Download.State]) {
        var progress: Double?
        for case let .downloading(running) in states where progress == nil { progress = running }
        if let progress {
            self = .downloading(progress)
        } else if states.contains(.failed) {
            self = .failed
        } else {
            self = states.isEmpty ? .none : .downloaded
        }
    }

    var spoken: String? {
        switch self {
        case .none: nil
        case .downloading: "Downloading"
        case .failed: "Download failed"
        case .downloaded: "Downloaded"
        }
    }
}

/// A Book standing on the shelf, spine out, its title read across the spine near the top.
///
/// A ribbon out of the top means it's being read, a knot of thread at the foot that it's downloaded,
/// and brown paper that Dogear can't open any of its ebook formats.
struct BookSpine: View {
    let book: Book
    let spine: Spine
    /// nil when the Book was never read.
    let throughBook: Double?
    let download: ShelfDownload
    let library: Library

    @Environment(CoverColors.self) private var coverColors
    @Environment(\.colorSchemeContrast) private var contrast

    private var cover: Cover? { book.ebookCover ?? book.cover }

    /// The format to stamp on the wrapping when no ebook file of the Book can be opened.
    private var unopenable: BookFile.Format? {
        let ebooks = book.files.filter { $0.format != .audiobook }
        return ebooks.contains(where: \.isSupported) ? nil : ebooks.first?.format
    }

    /// The first author's surname, set small at the foot as publishers do. Grimmory gives some
    /// names surname first ("Dinniman, Matt").
    private var authorLine: String? {
        guard let author = book.authors.first?.trimmingCharacters(in: .whitespaces), !author.isEmpty else { return nil }
        if let comma = author.firstIndex(of: ",") {
            return String(author[..<comma]).trimmingCharacters(in: .whitespaces).uppercased()
        }
        return author.split(separator: " ").last.map(String.init)?.uppercased()
    }

    var body: some View {
        let wrapped = unopenable != nil
        let bound = wrapped
            ? (spine: Theme.kraft, lettering: SpineColor.ink)
            : (coverColors.color(of: cover) ?? spine.fallbackColor).shelved
        let lettering = Color(bound.lettering)
        let titleSize = SpineType.size(for: spine.title, preferred: spine.fontSize, width: spine.thickness - SpineType.sidePadding * 2)
        VStack(spacing: 0) {
            if !wrapped {
                Bands(color: lettering).padding(.top, 7)
            }
            Text(spine.title)
                .font(SpineType.swiftUIFont(titleSize))
                .foregroundStyle(lettering)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .lineSpacing(-1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, SpineType.sidePadding)
                .padding(.top, wrapped ? 14 : 10)
                .shadow(color: .black.opacity(bound.lettering == .foil ? 0.35 : 0), radius: 0, y: 1)
            Spacer(minLength: 4)
            if !wrapped, contrast != .increased {
                // Line art stamped in the same foil or ink as the title.
                Image(systemName: SpineType.ornament(for: book.id))
                    .font(.system(size: min(spine.thickness * 0.36, 26), weight: .ultraLight))
                    .foregroundStyle(lettering.opacity(0.8))
            }
            Spacer(minLength: 4)
            if let authorLine, !wrapped {
                Text(authorLine)
                    .font(.system(size: 10, weight: .medium, design: .serif))
                    .tracking(0.9)
                    .foregroundStyle(lettering.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)
            }
            foot
                .frame(minHeight: 12)
            if !wrapped {
                Bands(color: lettering).padding(.bottom, 7)
            }
        }
        .frame(width: spine.thickness, height: spine.height)
        .background(Color(bound.spine))
        .overlay {
            if contrast != .increased {
                ZStack {
                    // Cloth: a fine mottle, light and dark.
                    Speckle(density: 6, opacity: 0.09)
                        .blendMode(.overlay)
                    // Light falling across a rounded back from the upper left.
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.38), location: 0),
                            .init(color: .black.opacity(0.05), location: 0.12),
                            .init(color: .white.opacity(0.13), location: 0.32),
                            .init(color: .clear, location: 0.6),
                            .init(color: .black.opacity(0.2), location: 0.88),
                            .init(color: .black.opacity(0.42), location: 1),
                        ],
                        startPoint: .leading, endPoint: .trailing
                    )
                    LinearGradient(colors: [.white.opacity(0.08), .clear, .black.opacity(0.18)], startPoint: .top, endPoint: .bottom)
                }
                .allowsHitTesting(false)
            }
        }
        // The headcap catching the light.
        .overlay(alignment: .top) { Color.white.opacity(0.18).frame(height: 1) }
        .clipShape(.rect(topLeadingRadius: 4, bottomLeadingRadius: 1.5, bottomTrailingRadius: 1.5, topTrailingRadius: 4))
        .overlay(alignment: .top) {
            if throughBook != nil {
                Ribbon()
                    .fill(LinearGradient(colors: [Theme.ribbonDark, Theme.ribbon, Theme.ribbonDark], startPoint: .leading, endPoint: .trailing))
                    .frame(width: 7, height: 26)
                    .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                    .offset(x: spine.thickness / 4, y: -14)
            }
        }
        .opacity(wrapped ? 0.92 : 1)
        // A short contact shadow where the Book stands on the ledge, and its shade on the back panel.
        .background(alignment: .bottom) {
            Ellipse()
                .fill(.black.opacity(0.55))
                .frame(width: spine.thickness * 1.05, height: 6)
                .blur(radius: 2.5)
                .offset(y: 2)
        }
        .shadow(color: .black.opacity(0.45), radius: 4, x: 3, y: 0)
        .task(id: cover) { await coverColors.load(cover, from: library) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    @ViewBuilder private var foot: some View {
        if let unopenable {
            Text(unopenable.name.uppercased())
                .font(.system(size: 7, weight: .heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(Theme.ribbon)
                .padding(.horizontal, 1)
                .overlay { Rectangle().strokeBorder(Theme.ribbon, lineWidth: 1) }
                .padding(.horizontal, 2)
                .padding(.bottom, 6)
        } else {
            switch download {
            case .none:
                EmptyView()
            case let .downloading(progress):
                Capsule()
                    .fill(.black.opacity(0.45))
                    .frame(height: 3)
                    .overlay(alignment: .leading) {
                        GeometryReader { track in
                            Capsule()
                                .fill(Theme.glow)
                                .frame(width: track.size.width * progress)
                                .shadow(color: Theme.glow, radius: 3)
                        }
                    }
                    .padding(.horizontal, 3)
                    .padding(.bottom, 4)
            case .failed:
                Image(systemName: "exclamationmark")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 13, height: 13)
                    .background(Theme.ribbon, in: .circle)
                    .padding(.bottom, 3)
            case .downloaded:
                Circle()
                    .fill(RadialGradient(
                        colors: Theme.thread,
                        center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 5
                    ))
                    .frame(width: 7, height: 7)
                    .padding(.bottom, 5)
            }
        }
    }

    /// Everything the list row used to say: title, authors, formats, progress and Downloads.
    private var spoken: String {
        var parts = [book.title]
        if !book.authors.isEmpty { parts.append(book.authors.formatted(.list(type: .and))) }
        parts.append(contentsOf: BookFormats.labels(for: book.files))
        if let throughBook { parts.append("\(throughBook.formatted(.percent.precision(.fractionLength(0)))) read") }
        if let spoken = download.spoken { parts.append(spoken) }
        return parts.joined(separator: ", ")
    }
}

enum BookFormats {
    /// Each format once, with formats Dogear can't open marked as such.
    static func labels(for files: [BookFile]) -> [String] {
        files.reduce(into: []) { labels, file in
            let label = file.isSupported ? file.format.name : "\(file.format.name) (format not supported)"
            if !labels.contains(label) { labels.append(label) }
        }
    }
}

/// A pair of gilt rules across a spine, a heavy one and a fine one.
private struct Bands: View {
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            color.frame(height: 1.5)
            color.frame(height: 0.75)
        }
        .padding(.horizontal, 2)
        .opacity(0.85)
    }
}

/// The spine's lettering: a serif title fitted so no word breaks across lines, and the stamped
/// art under it.
enum SpineType {
    /// Inside each edge of the spine, clear of its rounded shading.
    static let sidePadding: CGFloat = 6
    /// Below this a long word ellipsizes instead of shrinking further.
    static let minimumSize: CGFloat = 12

    static func swiftUIFont(_ size: CGFloat) -> Font { .system(size: size, weight: .medium, design: .serif) }

    private static func uiFont(_ size: CGFloat) -> UIFont {
        let system = UIFont.systemFont(ofSize: size, weight: .medium)
        return UIFont(descriptor: system.fontDescriptor.withDesign(.serif) ?? system.fontDescriptor, size: size)
    }

    /// How wide the title's longest word is at `size`.
    static func longestWord(in title: String, size: CGFloat) -> CGFloat {
        let font = uiFont(size)
        return title.split(whereSeparator: \.isWhitespace)
            .map { (String($0) as NSString).size(withAttributes: [.font: font]).width.rounded(.up) }
            .max() ?? 0
    }

    /// The width a spine needs for its longest word at the smallest standard size.
    static func neededThickness(for title: String) -> CGFloat {
        longestWord(in: title, size: CGFloat(Spine.fontSizes.lowerBound)) + sidePadding * 2 + 2
    }

    /// The biggest size up to `preferred` at which every word fits across `width`.
    static func size(for title: String, preferred: Double, width: CGFloat) -> CGFloat {
        var size = CGFloat(preferred)
        while size > minimumSize, longestWord(in: title, size: size) > width {
            size -= 0.5
        }
        return size
    }

    /// Line art for a spine, the same for a Book every time.
    static func ornament(for id: Int) -> String {
        ornaments[abs(id) % ornaments.count]
    }

    private static let ornaments = [
        "mountain.2", "water.waves", "sun.horizon", "building.columns", "leaf", "bird",
        "moon.stars", "tree", "sailboat", "crown", "fish", "camera.macro",
    ]
}

/// A ribbon bookmark with a swallowtail end.
nonisolated struct Ribbon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.16))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
