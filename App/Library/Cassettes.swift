import DogearCore
import SwiftUI

/// An audiobook in the rack: a cassette case seen edge-on, its paper insert carrying the title.
struct CassetteCase: View {
    let book: Book
    /// nil when the Book was never played.
    let throughBook: Double?
    let download: ShelfDownload
    let library: Library

    @Environment(CoverColors.self) private var coverColors

    private var cover: Cover? { book.audiobookCover ?? book.cover }
    private var canPlay: Bool { book.files.contains { $0.format == .audiobook && $0.isSupported } }

    var body: some View {
        let stripe = coverColors.color(of: cover) ?? Spine(book: book).fallbackColor
        HStack(spacing: 8) {
            Color(stripe).frame(width: 10)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    title
                    author
                }
                title
            }
            Spacer(minLength: 0)
            if let throughBook {
                Text(throughBook.formatted(.percent.precision(.fractionLength(0))))
                    .font(.custom("Noteworthy-Bold", fixedSize: 11))
                    .foregroundStyle(Theme.ribbon)
                    .padding(.horizontal, 5)
                    .overlay { Capsule().strokeBorder(Theme.ribbon, lineWidth: 1.5) }
                    .rotationEffect(.degrees(-5))
            }
            badge
        }
        .padding(.trailing, 8)
        .frame(height: 28)
        .background(Theme.paper)
        .clipShape(.rect(cornerRadius: 1))
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        // The clear plastic case around the insert.
        .background(
            LinearGradient(
                stops: [
                    .init(color: .white.opacity(0.55), location: 0),
                    .init(color: .white.opacity(0.18), location: 0.18),
                    .init(color: .white.opacity(0.08), location: 0.8),
                    .init(color: .white.opacity(0.3), location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            ),
            in: .rect(cornerRadius: 2)
        )
        .opacity(canPlay ? 1 : 0.7)
        .shadow(color: .black.opacity(0.6), radius: 1.5, y: 2)
        .task(id: cover) { await coverColors.load(cover, from: library) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var title: some View {
        Text(Spine.title(for: book.title))
            .font(Theme.marker(15))
            .foregroundStyle(Theme.pen)
            .lineLimit(1)
    }

    @ViewBuilder private var author: some View {
        if let author = book.authors.first {
            Text(author)
                .font(.custom("Noteworthy-Light", fixedSize: 12))
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(1)
                .fixedSize()
        }
    }

    @ViewBuilder private var badge: some View {
        switch download {
        case .none:
            EmptyView()
        case let .downloading(progress):
            ProgressView(value: progress)
                .tint(Color(hex: 0x2F8A5A))
                .frame(width: 40)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.ribbon)
        case .downloaded:
            Image(systemName: "arrow.down.circle.fill").foregroundStyle(Theme.ink)
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

/// A cassette seen face-on. The tape on its reels is how far through the audiobook the listener is.
struct CassetteFace: View {
    static let size = CGSize(width: 170, height: 108)

    let title: String
    /// 0…1.
    let throughBook: Double
    let stripe: Color

    var body: some View {
        let reels = TapeReels(throughBook: throughBook, hub: 8, full: 20)
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 7)
                .fill(LinearGradient(colors: Theme.cassetteShell, startPoint: .top, endPoint: .bottom))
            VStack(spacing: 0) {
                Theme.paper
                stripe.frame(height: 24)
            }
            .frame(height: 64)
            .clipShape(.rect(cornerRadius: 3))
            .padding(.horizontal, 9)
            .padding(.top, 8)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(Theme.marker(12))
                    .foregroundStyle(Theme.pen)
                Text(throughBook.formatted(.percent.precision(.fractionLength(0))))
                    .font(.custom("Noteworthy-Bold", fixedSize: 10))
                    .foregroundStyle(Theme.inkSoft)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            // The window onto the reels.
            ZStack {
                LinearGradient(colors: [Color(hex: 0x1A1410), Color(hex: 0x3A2A20)], startPoint: .top, endPoint: .bottom)
                reel(tape: reels.supply).offset(x: -27)
                reel(tape: reels.takeUp).offset(x: 27)
            }
            .frame(width: 84, height: 28)
            .clipShape(.capsule)
            .overlay { Capsule().strokeBorder(.white.opacity(0.65), lineWidth: 2) }
            .padding(.top, 40)
            CassetteFoot()
                .fill(LinearGradient(colors: [Color(hex: 0x232325), Color(hex: 0x1A1A1C)], startPoint: .top, endPoint: .bottom))
                .frame(width: 110, height: 22)
                .padding(.top, Self.size.height - 22)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .shadow(color: .black.opacity(0.6), radius: 6, y: 6)
    }

    private func reel(tape radius: Double) -> some View {
        ZStack {
            Circle().fill(Theme.tape).frame(width: radius * 2, height: radius * 2)
            Circle().fill(.white).frame(width: 14, height: 14)
            Circle().fill(Color(hex: 0x2A1A10)).frame(width: 6, height: 6)
        }
    }
}

/// The raised section at the bottom of a cassette shell, wider at the base.
private nonisolated struct CassetteFoot: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.08, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
