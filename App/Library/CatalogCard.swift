import DogearCore
import SwiftUI

/// A Book pulled off the shelf: its cover and a library catalog card with what the spine has no
/// room for, and the ways to open, download or remove each of its Book files.
struct CatalogCard: View {
    let book: Book
    let library: Library
    /// nil when the Book was never read.
    let throughBook: Double?
    /// The Book files that can be opened, one per format.
    let openable: [BookFile]
    @Binding var downloadProblem: String?
    let open: (BookFile) -> Void
    let putBack: () -> Void

    @Environment(AppModel.self) private var model

    private var onDevice: [String] {
        book.files.compactMap { file in
            guard let download = model.downloadList.download(bookFileID: file.id), download.state == .finished else { return nil }
            return "\(file.format.name), \(DownloadsView.size(download.bytes))"
        }
    }

    /// Why each failed Download stopped, which the shelf only marks with a "!".
    private var failures: [String] {
        book.files.compactMap { file in
            guard let download = model.downloadList.download(bookFileID: file.id), download.state == .failed else { return nil }
            return "\(file.format.name) download failed. \(download.failure?.message ?? "It stopped before it finished.")"
        }
    }

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @AccessibilityFocusState private var isCardFocused: Bool

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        Spacer()
                        Button("Put Back", systemImage: "xmark", action: putBack)
                            .labelStyle(.iconOnly)
                            .font(.headline)
                            .foregroundStyle(palette.ink)
                            .frame(width: 44, height: 44)
                            .background(palette.raised, in: .circle)
                            .overlay { Circle().strokeBorder(palette.boundary, lineWidth: 1) }
                    }
                    CoverImage(cover: book.cover, title: book.title, library: library)
                        // Shrinks first on a short screen or at large text sizes.
                        .frame(height: max(110, min(typeSize.isAccessibilitySize ? 140 : 190, proxy.size.height * 0.28)))
                        .shadow(color: .black.opacity(0.4), radius: 10, x: 6, y: 8)
                        .rotationEffect(.degrees(reduceMotion ? 0 : -2.5))
                        .accessibilityHidden(true)
                        // The cover and the card are the Book in hand; only a tap beside them puts it back.
                        .onTapGesture {}
                    card
                        .onTapGesture {}
                        .accessibilityFocused($isCardFocused)
                    VStack(spacing: 12) {
                        ForEach(Array(openable.enumerated()), id: \.element.id) { index, file in
                            let title = file.format == .audiobook ? "Listen" : "Read \(file.format.name)"
                            if index == 0 {
                                Button(title) { open(file) }
                                    .buttonStyle(FilledActionStyle())
                            } else {
                                Button(title) { open(file) }
                                    .buttonStyle(OutlinedActionStyle())
                            }
                        }
                        DownloadMenu(book: book, problem: $downloadProblem)
                            .buttonStyle(OutlinedActionStyle())
                    }
                }
                .padding(20)
                .frame(maxWidth: 520)
                // Fills the screen so a tap anywhere beside the Book lands here: a scroll view takes
                // the touches a view behind it would have had.
                .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .top)
                .contentShape(.rect)
                .onTapGesture(perform: putBack)
            }
            // Pulled down past the top, the Book goes back, like a sheet swiped away.
            .modifier(PullsDownToClose(close: putBack))
        }
        .background {
            CanvasBackground()
                .opacity(0.98)
                .accessibilityHidden(true)
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, putBack)
        .onAppear { isCardFocused = true }
    }

    /// One ruled paper card, a line per field, so the rules stay under the text at any size.
    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(book.title)
                .serifTitle(24, relativeTo: .title2)
                .foregroundStyle(palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 4)
            if !book.authors.isEmpty {
                Text(book.authors.formatted(.list(type: .and)))
                    .font(.body)
                    .foregroundStyle(palette.inkSecondary)
                    .padding(.bottom, 10)
            }
            line("Formats", BookFormats.labels(for: book.files).joined(separator: " · "))
            if let throughBook {
                line("Progress", "\(throughBook.formatted(.percent.precision(.fractionLength(0)))) through")
            }
            if !onDevice.isEmpty {
                line("On this device", onDevice.joined(separator: " · "))
            }
            ForEach(failures, id: \.self) { failure in
                Text(failure)
                    .font(.subheadline)
                    .foregroundStyle(palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    .overlay(alignment: .top) { palette.outline.frame(height: 1) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .paperCard(radius: 12)
        .accessibilityElement(children: .combine)
    }

    private func line(_ label: String, _ value: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .foregroundStyle(palette.inkSecondary)
                Spacer(minLength: 12)
                Text(value)
                    .foregroundStyle(palette.ink)
                    .multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label).foregroundStyle(palette.inkSecondary)
                Text(value).foregroundStyle(palette.ink)
            }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .overlay(alignment: .top) { palette.outline.frame(height: 1) }
    }
}
