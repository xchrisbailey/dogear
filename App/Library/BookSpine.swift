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

/// A Book standing on the shelf, spine out.
///
/// A ribbon out of the top means it's being read, a brass pin at the foot that it's downloaded,
/// and brown paper that Dogear can't open any of its ebook formats.
struct BookSpine: View {
    let book: Book
    let spine: Spine
    /// nil when the Book was never read.
    let throughBook: Double?
    let download: ShelfDownload
    let library: Library

    @Environment(CoverColors.self) private var coverColors

    private var cover: Cover? { book.ebookCover ?? book.cover }

    /// The format to stamp on the wrapping when no ebook file of the Book can be opened.
    private var unopenable: BookFile.Format? {
        let ebooks = book.files.filter { $0.format != .audiobook }
        return ebooks.contains(where: \.isSupported) ? nil : ebooks.first?.format
    }

    var body: some View {
        let wrapped = unopenable != nil
        let bound = wrapped
            ? (spine: Theme.kraft, lettering: SpineColor.ink)
            : (coverColors.color(of: cover) ?? spine.fallbackColor).shelved
        let lettering = Color(bound.lettering)
        // Clear of the bands at the head and the pin at the foot.
        let room = spine.height - 46
        ZStack {
            Color(bound.spine)
            // Light falling across a rounded back.
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.42), location: 0),
                    .init(color: .white.opacity(0.16), location: 0.28),
                    .init(color: .white.opacity(0.04), location: 0.55),
                    .init(color: .black.opacity(0.38), location: 1),
                ],
                startPoint: .leading, endPoint: .trailing
            )
            if !wrapped {
                VStack {
                    Bands(color: lettering)
                    Spacer()
                    Bands(color: lettering)
                }
                .padding(.top, 8)
                .padding(.bottom, 16)
                .padding(.horizontal, 3)
            }
            // Laid out sideways, then turned to read top to bottom; the overlay keeps the turned
            // text from widening the spine.
            Color.clear
                .frame(width: spine.thickness, height: room)
                .overlay {
                    Text(spine.title.uppercased())
                        .font(Theme.stamped(spine.fontSize))
                        .tracking(0.6)
                        .lineLimit(1)
                        .minimumScaleFactor(11 / spine.fontSize)
                        .truncationMode(.tail)
                        .foregroundStyle(lettering)
                        .frame(width: room, height: spine.thickness)
                        .rotationEffect(.degrees(90))
                }
        }
        .frame(width: spine.thickness, height: spine.height)
        .clipShape(.rect(topLeadingRadius: 3, bottomLeadingRadius: 1, bottomTrailingRadius: 1, topTrailingRadius: 3))
        .overlay(alignment: .bottom) { foot }
        .overlay(alignment: .top) {
            if throughBook != nil {
                Ribbon()
                    .fill(Theme.ribbon)
                    .frame(width: 6, height: 26)
                    .offset(x: spine.thickness / 5, y: -14)
            }
        }
        .opacity(wrapped ? 0.85 : 1)
        .shadow(color: .black.opacity(0.35), radius: 1.5, x: 2)
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
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(Color(hex: 0xFF9A8A))
                    .padding(.bottom, 4)
            case .downloaded:
                Circle()
                    .fill(RadialGradient(
                        colors: [Theme.brass[0], Theme.brass[1], Theme.engraved],
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

/// A pair of gilt rules across a spine.
private struct Bands: View {
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            color.frame(height: 1)
            color.frame(height: 1)
        }
        .opacity(0.8)
    }
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
