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
        let shellColor = Color(coverColors.color(of: cover) ?? Spine(book: book).fallbackColor)
        CassetteDrawing(title: Spine.title(for: book.title), shell: shellColor, labelLines: 2) {
            HStack(spacing: 4) {
                if let throughBook {
                    Capsule()
                        .fill(.black.opacity(0.35))
                        .frame(height: 3)
                        .overlay(alignment: .leading) {
                            GeometryReader { track in
                                Capsule().fill(palette.raised).frame(width: track.size.width * throughBook)
                            }
                        }
                } else {
                    Spacer(minLength: 0)
                }
                badge
            }
        }
        .aspectRatio(Self.ratio, contentMode: .fit)
        .padding(3)
        // The clear plastic case around the cassette.
        .background {
            RoundedRectangle(cornerRadius: 4)
                .fill(LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.4), location: 0),
                        .init(color: .white.opacity(0.12), location: 0.2),
                        .init(color: .white.opacity(0.06), location: 0.8),
                        .init(color: .white.opacity(0.25), location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                ))
            RoundedRectangle(cornerRadius: 4).strokeBorder(.white.opacity(0.45), lineWidth: 1)
        }
        .opacity(canPlay ? 1 : 0.7)
        .shadow(color: .black.opacity(0.35), radius: 2, y: 2)
        .task(id: cover) { await coverColors.load(cover, from: library) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
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

/// A cassette seen face on: a colored shell, a paper label with the title in its top half, and
/// the two reels in a window below it. `marks` sits along the foot, clear of the title.
struct CassetteDrawing<Marks: View>: View {
    let title: String
    let shell: Color
    var labelLines = 2
    /// 0…1, for the tape on the reels; nil leaves them half wound.
    var throughBook: Double?
    @ViewBuilder var marks: Marks

    @Environment(\.palette) private var palette

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let inset = size.width * 0.06
            VStack(spacing: size.height * 0.04) {
                // The label: paper over the top half, lettered in ink.
                Text(title)
                    .font(Theme.stamped(13))
                    .foregroundStyle(palette.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(labelLines)
                    .minimumScaleFactor(0.85)
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity, minHeight: size.height * 0.42, maxHeight: size.height * 0.5)
                    .background(palette.raised, in: .rect(cornerRadius: 2))
                reels(height: size.height * 0.22)
                marks
                    .frame(height: 8)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, inset)
            .padding(.top, inset)
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(shell, in: .rect(cornerRadius: 5))
            .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(.black.opacity(0.2), lineWidth: 1) }
        }
    }

    private func reels(height: CGFloat) -> some View {
        let reels = TapeReels(throughBook: throughBook ?? 0.5, hub: height * 0.22, full: height * 0.48)
        return HStack {
            reel(tape: reels.supply, height: height)
            Spacer(minLength: 0)
            reel(tape: reels.takeUp, height: height)
        }
        .padding(.horizontal, height * 0.6)
        .frame(height: height)
        .background(LinearGradient(colors: Theme.window, startPoint: .top, endPoint: .bottom), in: .capsule)
        .accessibilityHidden(true)
    }

    private func reel(tape radius: Double, height: CGFloat) -> some View {
        ZStack {
            Circle().fill(Theme.tape).frame(width: radius * 2, height: radius * 2)
            Circle().fill(Color(hex: 0xEDE6D8)).frame(width: height * 0.42, height: height * 0.42)
        }
        .frame(width: height, height: height)
    }
}

extension CassetteDrawing where Marks == EmptyView {
    init(title: String, shell: Color, labelLines: Int = 2, throughBook: Double? = nil) {
        self.init(title: title, shell: shell, labelLines: labelLines, throughBook: throughBook) { EmptyView() }
    }
}
