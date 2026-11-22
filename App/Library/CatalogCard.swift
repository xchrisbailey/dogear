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

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                    HStack {
                        Spacer()
                        Button("Put Back", systemImage: "xmark", action: putBack)
                            .labelStyle(.iconOnly)
                            .font(.headline)
                            .foregroundStyle(Theme.accent)
                            .frame(width: 44, height: 44)
                            .background(Theme.backPanel, in: .circle)
                    }
                    CoverImage(cover: book.cover, library: library)
                        .frame(height: 220)
                        .shadow(color: .black.opacity(0.7), radius: 14, x: 8, y: 12)
                        .rotationEffect(.degrees(-3))
                        .accessibilityHidden(true)
                        // The cover and the card are the Book in hand; only a tap beside them puts it back.
                        .onTapGesture {}
                    card
                        .onTapGesture {}
                    VStack(spacing: 12) {
                        ForEach(openable) { file in
                            Button(file.format == .audiobook ? "Listen" : "Read \(file.format.name)") { open(file) }
                                .buttonStyle(CardKeyStyle())
                        }
                        DownloadMenu(book: book, problem: $downloadProblem)
                            .buttonStyle(LeatherTabStyle(isOn: false))
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
            FeltBackground()
                .opacity(0.97)
                .accessibilityHidden(true)
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, putBack)
    }

    /// Typed lines, each on its own rule, so the rules stay under the text at any text size.
    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("DOGEAR LIBRARY")
                .font(.custom("AmericanTypewriter", size: 11))
                .tracking(1.5)
                .foregroundStyle(Theme.ribbon)
                .padding(.bottom, 6)
                .accessibilityHidden(true)
            line(book.title, size: 18)
            if !book.authors.isEmpty {
                line(book.authors.formatted(.list(type: .and)))
            }
            line("Formats", BookFormats.labels(for: book.files).joined(separator: " · "))
            if !onDevice.isEmpty {
                line("On this device", onDevice.joined(separator: " · "))
            }
            ForEach(failures, id: \.self) { failure in
                line(failure)
            }
            if let throughBook {
                Text("\(throughBook.formatted(.percent.precision(.fractionLength(0)))) READ")
                    .font(.custom("AmericanTypewriter-Bold", size: 13))
                    .foregroundStyle(Theme.ribbon)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .overlay { RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.ribbon, lineWidth: 2) }
                    .rotationEffect(.degrees(-4))
                    .padding(.top, 14)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(hex: 0xF3EAD0), in: .rect(cornerRadius: 4))
        .shadow(color: .black.opacity(0.65), radius: 14, y: 12)
        // Paper is light whatever the device's appearance.
        .environment(\.colorScheme, .light)
        .accessibilityElement(children: .combine)
    }

    private func line(_ text: String, size: CGFloat = 14) -> some View {
        Text(text)
            .font(.custom("AmericanTypewriter", size: size))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .bottomLeading)
            .padding(.bottom, 3)
            .overlay(alignment: .bottom) { Rule() }
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack(alignment: .lastTextBaseline) {
            Text(label.uppercased())
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.custom("AmericanTypewriter", size: 13))
        .foregroundStyle(Theme.ink)
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .bottom)
        .padding(.bottom, 3)
        .overlay(alignment: .bottom) { Rule() }
    }

    /// The blue ruling of an index card.
    private struct Rule: View {
        var body: some View {
            Color(red: 0.27, green: 0.43, blue: 0.63).opacity(0.35).frame(height: 1)
        }
    }
}

/// A typewriter key, for what the card can do with the Book.
private struct CardKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.custom("AmericanTypewriter-Bold", size: 16))
            .foregroundStyle(Theme.paper)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(
                LinearGradient(colors: [Color(hex: 0x8C2A2A), Color(hex: 0x5E1515)], startPoint: .top, endPoint: .bottom),
                in: .rect(cornerRadius: 6)
            )
            .offset(y: configuration.isPressed ? 2 : 0)
    }
}
