import DogearCore
import Foundation
@preconcurrency import ReadiumNavigator
@preconcurrency import ReadiumShared
@preconcurrency import ReadiumStreamer

/// Opens a Server PDF in Readium's navigator, keeps the reader's Position on the device and
/// shares it with Grimmory's web reader as a page number.
@Observable
final class PDFReaderModel: PDFNavigatorDelegate {
    enum State {
        case opening
        case reading(PDFNavigatorViewController)
        case failed(String)
    }

    private(set) var state: State = .opening
    /// 1-based, like the web reader.
    private(set) var page: Int?
    private(set) var pageCount: Int?
    private(set) var tableOfContents: [Link] = []
    var isShowingControls = true

    private let bookFileID: Int
    private let pdf: ServerPDF
    private let positions: Positions?
    private let sharedPositions: SharedPositions?
    private let pageTurns = DirectionalNavigationAdapter()
    private var recording: Task<Void, Never>?
    /// The first location is where the reader opened, not new reading.
    private var hasLanded = false
    private var pushing: Task<Void, Never>?
    private static let pushDelay = Duration.seconds(3)

    init(pdf: ServerPDF, bookFileID: Int, positions: Positions?, sharedPositions: SharedPositions?) {
        self.pdf = pdf
        self.bookFileID = bookFileID
        self.positions = positions
        self.sharedPositions = sharedPositions
    }

    private var navigator: PDFNavigatorViewController? {
        if case let .reading(navigator) = state { navigator } else { nil }
    }

    func open() async {
        guard case .opening = state else { return }
        do {
            let publication = try await openPublication()
            tableOfContents = (try? await publication.tableOfContents().get()) ?? []
            pageCount = try? await publication.positions().get().count
            let navigator = try PDFNavigatorViewController(
                publication: publication,
                initialLocation: await resumeLocation(in: publication),
                config: .init(),
                delegate: self
            )
            pageTurns.bind(to: navigator)
            state = .reading(navigator)
        } catch {
            state = .failed("Couldn't open this PDF. Check your connection and try again.")
        }
    }

    /// PDFKit can't read from a stream, so the whole PDF is fetched into Caches (not a Download)
    /// and opened from there.
    private func openPublication() async throws -> Publication {
        let file = try await fetch()
        guard let url = FileURL(url: file) else { throw OpenError.notAFile }
        let httpClient = DefaultHTTPClient()
        let asset = try await AssetRetriever(httpClient: httpClient).retrieve(url: url, mediaType: .pdf).get()
        let opener = PublicationOpener(parser: DefaultPublicationParser(
            httpClient: httpClient,
            assetRetriever: AssetRetriever(httpClient: httpClient),
            pdfFactory: DefaultPDFDocumentFactory()
        ))
        return try await opener.open(asset: asset, allowUserInteraction: false).get()
    }

    private func fetch() async throws -> URL {
        let directory = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "PDFs")
        let file = directory.appending(path: "\(pdf.bookID).pdf")
        do {
            let contents = try await pdf.contents()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try contents.write(to: file, options: .atomic)
        } catch {
            // Offline, the copy from the last time it opened still reads, if iOS hasn't purged it.
            guard FileManager.default.fileExists(atPath: file.path) else { throw error }
        }
        return file
    }

    /// Where to start: the newer of this device's Position and the Shared position (ADR 0002).
    /// Offline, only the device's.
    private func resumeLocation(in publication: Publication) async -> Locator? {
        let local = await positions?.latest(bookFileID: bookFileID)
        let shared = try? await sharedPositions?.latest(.pdf, bookID: pdf.bookID, bookFileID: bookFileID)
        let newest = [local, shared].compactMap(\.self).max { $0.recordedAt < $1.recordedAt }
        guard case let .pdf(saved)? = newest?.location, let link = publication.readingOrder.first else { return nil }
        return Locator(
            href: link.url(),
            mediaType: .pdf,
            locations: .init(fragments: ["page=\(saved.page)"], position: saved.page)
        )
    }

    func go(to link: Link) async {
        _ = await navigator?.go(to: link, options: NavigatorGoOptions(animated: false))
    }

    // MARK: PDFNavigatorDelegate

    func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
        guard let page = locator.locations.page ?? locator.locations.position else { return }
        // Spreads and zooming report the same page again; only a new page is new reading.
        guard page != self.page else { return }
        self.page = page
        record(page, share: hasLanded)
        hasLanded = true
    }

    private func record(_ page: Int, share: Bool) {
        // Matches the web reader, which shares page ÷ page count.
        let bookProgress = pageCount.map { Double(page) / Double(max($0, 1)) } ?? 0
        let location = Position.Location.pdf(PDFLocation(page: page, bookProgress: bookProgress))
        // Chained so a slow save can't land after a newer one and win.
        recording = Task { [previous = recording, positions, sharedPositions, bookFileID, bookID = pdf.bookID] in
            await previous?.value
            guard let positions else {
                // Without the on-device store there's no Outbox; sharing directly is the best left.
                if share {
                    let position = Position(bookFileID: bookFileID, location: location, recordedAt: Date())
                    try? await sharedPositions?.push(position, bookID: bookID)
                }
                return
            }
            if share {
                _ = try? await positions.record(location, bookFileID: bookFileID, bookID: bookID)
                self.pushSoon()
            } else {
                _ = try? await positions.recordLanding(location, bookFileID: bookFileID)
            }
        }
    }

    /// Page turns come in bursts; the Outbox is pushed once the reader settles on a page.
    private func pushSoon() {
        pushing?.cancel()
        pushing = Task { [positions, sharedPositions] in
            try? await Task.sleep(for: Self.pushDelay)
            guard !Task.isCancelled, let positions, let sharedPositions else { return }
            try? await positions.flushOutbox(to: sharedPositions)
        }
    }

    /// Pushes the last page read now rather than after the delay. Failures stay in the Outbox.
    func close() async {
        pushing?.cancel()
        await recording?.value
        guard let positions, let sharedPositions else { return }
        try? await positions.flushOutbox(to: sharedPositions)
    }

    func navigator(_ navigator: VisualNavigator, didTapAt point: CGPoint) {
        isShowingControls.toggle()
    }

    func navigator(_ navigator: Navigator, presentError error: NavigatorError) {}

    private enum OpenError: Error {
        case notAFile
    }
}
