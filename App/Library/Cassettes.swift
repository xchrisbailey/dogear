import DogearCore
import SwiftUI

/// An audiobook on its shelf: a cassette in its clear case, face out, the title on its paper
/// label. The same in every theme. Progress and Download marks sit under the title, never on it.
struct CassetteCase: View {
    /// Width over height.
    static let ratio = CassetteArt.ratio

    let book: Book
    /// nil when the Book was never played.
    let throughBook: Double?
    let download: ShelfDownload

    @Environment(\.palette) private var palette

    private var canPlay: Bool { book.files.contains { $0.format == .audiobook && $0.isSupported } }

    var body: some View {
        CassetteArt(title: Spine.title(for: book.title))
            .overlay {
                GeometryReader { proxy in
                    marks
                        .frame(width: proxy.size.width * 0.8, height: 6)
                        .position(x: proxy.size.width / 2, y: proxy.size.height * 0.368)
                }
            }
            .opacity(canPlay ? 1 : 0.7)
            // Standing on the ledge: a contact shadow at its foot.
            .background(alignment: .bottom) {
                Ellipse().fill(.black.opacity(0.45)).frame(height: 6).blur(radius: 2.5).offset(y: 2)
            }
            .shadow(color: .black.opacity(0.3), radius: 3, x: 2, y: 1)
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

/// The cassette artwork, with a title written on its label when one is given. Without one the
/// label is left blank, for sizes too small to read.
struct CassetteArt: View {
    /// Width over height of the artwork.
    static let ratio: CGFloat = 1.5

    var title: String?

    /// Ink on the label, the same in every theme.
    private static let ink = Color(red: 0.18, green: 0.11, blue: 0.07)

    var body: some View {
        Image("CassetteCase")
            .resizable()
            .interpolation(.high)
            .aspectRatio(Self.ratio, contentMode: .fit)
            .overlay {
                if let title {
                    GeometryReader { proxy in
                        Text(title)
                            .font(.system(size: max(proxy.size.height * 0.118, 8), weight: .medium, design: .serif).italic())
                            .foregroundStyle(Self.ink)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                            .frame(width: proxy.size.width * 0.82, height: proxy.size.height * 0.2)
                            .position(x: proxy.size.width / 2, y: proxy.size.height * 0.242)
                    }
                }
            }
            .accessibilityHidden(true)
    }
}
