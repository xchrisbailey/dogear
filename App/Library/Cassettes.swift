import DogearCore
import SwiftUI

/// An audiobook on its shelf: a cassette in a clear case, face out, its paper label carrying the
/// title. The cassette's shell takes the cover's color. Progress and Download marks sit under the
/// label, never on the title.
struct CassetteCase: View {
    /// Width over height.
    static let ratio: CGFloat = 1.55

    let book: Book
    /// nil when the Book was never played.
    let throughBook: Double?
    let download: ShelfDownload
    let library: Library

    @Environment(CoverColors.self) private var coverColors
    @Environment(\.palette) private var palette

    private var cover: Cover? { book.audiobookCover ?? book.cover }
    private var canPlay: Bool { book.files.contains { $0.format == .audiobook && $0.isSupported } }

    var body: some View {
        let color = Color(coverColors.color(of: cover) ?? Spine(book: book).fallbackColor)
        Group {
            if palette.theme == .walnut {
                JCard(title: Spine.title(for: book.title), ornament: SpineType.ornament(for: book.id)) { marks }
            } else {
                CassetteDrawing(title: Spine.title(for: book.title), band: color, clearShell: palette.theme == .oak, throughBook: throughBook) { marks }
            }
        }
        .aspectRatio(Self.ratio, contentMode: .fit)
        .padding(4)
        .background { ClearCase() }
        .opacity(canPlay ? 1 : 0.7)
        // Standing on the ledge: a contact shadow at its foot.
        .background(alignment: .bottom) {
            Ellipse().fill(.black.opacity(0.45)).frame(height: 6).blur(radius: 2.5).offset(y: 2)
        }
        .shadow(color: .black.opacity(0.3), radius: 3, x: 2, y: 1)
        .task(id: cover) { await coverColors.load(cover, from: library) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    /// How far through, and the Download, along the foot of the case.
    private var marks: some View {
        HStack(spacing: 4) {
            if let throughBook {
                Capsule()
                    .fill(.black.opacity(0.18))
                    .frame(height: 3)
                    .overlay(alignment: .leading) {
                        GeometryReader { track in
                            Capsule().fill(palette.accent).frame(width: track.size.width * throughBook)
                        }
                    }
            } else {
                Spacer(minLength: 0)
            }
            badge
        }
    }

    @ViewBuilder private var badge: some View {
        switch download {
        case .none:
            EmptyView()
        case let .downloading(progress):
            ProgressView(value: progress)
                .tint(Theme.glow)
                .frame(width: 24)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.white, Theme.ribbon)
        case .downloaded:
            Circle()
                .fill(RadialGradient(colors: Theme.thread, center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 5))
                .frame(width: 7, height: 7)
        }
    }

    private var spoken: String {
        var parts = [book.title]
        if !book.authors.isEmpty { parts.append(book.authors.formatted(.list(type: .and))) }
        parts.append(contentsOf: BookFormats.labels(for: book.files))
        if let throughBook { parts.append("\(throughBook.formatted(.percent.precision(.fractionLength(0)))) played") }
        if let spoken = download.spoken { parts.append(spoken) }
        return parts.joined(separator: ", ")
    }
}

/// A clear plastic cassette case: faint, with a bright rim and glare across its face.
struct ClearCase: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(LinearGradient(colors: [.white.opacity(0.32), .white.opacity(0.12), .white.opacity(0.2)], startPoint: .top, endPoint: .bottom))
            .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(.white.opacity(0.65), lineWidth: 1) }
            .overlay { RoundedRectangle(cornerRadius: 3).strokeBorder(.black.opacity(0.15), lineWidth: 0.5).padding(2.5) }
            .overlay {
                // Glare across the lid.
                LinearGradient(
                    stops: [.init(color: .clear, location: 0.25), .init(color: .white.opacity(0.22), location: 0.32), .init(color: .clear, location: 0.42)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .clipShape(.rect(cornerRadius: 5))
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// A case's paper insert facing out: the title in italic, and line art printed under it.
struct JCard<Marks: View>: View {
    let title: String
    let ornament: String
    @ViewBuilder var marks: Marks

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 2) {
            Spacer(minLength: 2)
            Text(title)
                .font(.system(size: 14, weight: .medium, design: .serif).italic())
                .foregroundStyle(palette.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.93)
            Image(systemName: ornament)
                .font(.system(size: 15, weight: .ultraLight))
                .foregroundStyle(palette.inkSecondary)
            Spacer(minLength: 2)
            marks.frame(height: 6)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.raised)
        .overlay { Speckle(density: 10, opacity: 0.05) }
        .overlay { Rectangle().strokeBorder(palette.outline.opacity(0.7), lineWidth: 0.5).padding(3) }
        .clipShape(.rect(cornerRadius: 2))
    }
}

/// A cassette seen face on: its shell, colored or clear, and a paper label carrying the title
/// above a colored band with the window onto the reels. `marks` sits along the foot, clear of
/// the title.
struct CassetteDrawing<Marks: View>: View {
    let title: String
    /// The label's band, from the cover.
    let band: Color
    /// Clear plastic rather than the band's color.
    var clearShell = false
    /// 0…1, for the tape on the reels; nil leaves them half wound.
    var throughBook: Double?
    @ViewBuilder var marks: Marks

    @Environment(\.palette) private var palette

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let inset = max(size.width * 0.045, 3)
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium, design: .serif).italic())
                        .foregroundStyle(palette.ink)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.93)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(palette.raised)
                    band
                        .frame(height: size.height * 0.3)
                        .overlay { reels(height: size.height * 0.22, width: size.width) }
                }
                .clipShape(.rect(cornerRadius: 2))
                .frame(height: size.height * 0.72)
                marks
                    .frame(height: 6)
                    .padding(.horizontal, size.width * 0.12)
                    .frame(maxHeight: .infinity)
            }
            .padding(.horizontal, inset)
            .padding(.top, inset)
            .frame(width: size.width, height: size.height, alignment: .top)
            .background {
                RoundedRectangle(cornerRadius: 4)
                    .fill(clearShell ? AnyShapeStyle(Color.white.opacity(0.45)) : AnyShapeStyle(band.mix(with: .black, by: 0.25)))
                    .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(.black.opacity(0.18), lineWidth: 0.5) }
            }
        }
    }

    /// The window: tape wound on two hubs, their teeth showing.
    private func reels(height: CGFloat, width: CGFloat) -> some View {
        let reels = TapeReels(throughBook: throughBook ?? 0.5, hub: height * 0.26, full: height * 0.5)
        return ZStack {
            RoundedRectangle(cornerRadius: height * 0.2)
                .fill(LinearGradient(colors: Theme.window, startPoint: .top, endPoint: .bottom))
            HStack {
                reel(tape: reels.supply, height: height)
                Spacer(minLength: 0)
                reel(tape: reels.takeUp, height: height)
            }
            .padding(.horizontal, height * 0.15)
        }
        .frame(width: width * 0.62, height: height)
        .accessibilityHidden(true)
    }

    private func reel(tape radius: Double, height: CGFloat) -> some View {
        ZStack {
            Circle().fill(Theme.tape).frame(width: radius * 2, height: radius * 2)
            Circle().fill(Color(hex: 0xF2ECE0)).frame(width: height * 0.5, height: height * 0.5)
            ForEach(0 ..< 6, id: \.self) { tooth in
                Capsule()
                    .fill(Color(hex: 0x6B5B4B))
                    .frame(width: max(height * 0.06, 1), height: height * 0.14)
                    .offset(y: -height * 0.17)
                    .rotationEffect(.degrees(Double(tooth) * 60))
            }
        }
        .frame(width: height, height: height)
    }
}

extension CassetteDrawing where Marks == EmptyView {
    init(title: String, band: Color, clearShell: Bool = false, throughBook: Double? = nil) {
        self.init(title: title, band: band, clearShell: clearShell, throughBook: throughBook) { EmptyView() }
    }
}
