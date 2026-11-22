import DogearCore
import Foundation
@preconcurrency import ReadiumNavigator
@preconcurrency import ReadiumShared
@preconcurrency import ReadiumStreamer

/// Opens a Server PDF, or its Download, in Readium's navigator, keeps the reader's Position on the device and
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
    /// The Download's file; nil fetches the PDF from the Server.
    private let downloaded: URL?
    /// The fetched copy, deleted on close: keeping it would be a Download the account may not be allowed.
    private var fetched: URL?
    private let positions: Positions?
    private let sharedPositions: SharedPositions?
    private let pageTurns = DirectionalNavigationAdapter()
    private let recorder: PositionRecorder
    /// The first location is where the reader opened, not new reading.
    private var hasLanded = false
    private var pushing: Task<Void, Never>?
    private static let pushDelay = Duration.seconds(3)

    init(pdf: ServerPDF, downloaded: URL?, bookFileID: Int, positions: Positions?, sharedPositions: SharedPositions?) {
        self.pdf = pdf
        self.downloaded = downloaded
        self.bookFileID = bookFileID
        self.positions = positions
        self.sharedPositions = sharedPositions
        recorder = PositionRecorder(bookID: pdf.bookID, positions: positions, sharedPositions: sharedPositions)
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
                config: .init(preferences: .onDesk),
                delegate: self
            )
            pageTurns.bind(to: navigator)
            state = .reading(navigator)
        } catch let error as RequestError where error == .forbidden || error == .notFound {
            state = .failed(error.errorDescription ?? "Couldn't open this PDF.")
        } catch {
            state = .failed("Couldn't open this PDF. Check your connection and try again.")
        }
    }

    /// PDFKit can't read from a stream, so without a Download the whole PDF is fetched into a
    /// temporary file and opened from there.
    private func openPublication() async throws -> Publication {
        let file = if let downloaded { downloaded } else { try await fetch() }
        guard let url = FileURL(url: file) else { throw OpenError.notAFile }
        let httpClient = DefaultHTTPClient()
        let asset = try await AssetRetriever(httpClient: httpClient).retrieve(url: url, mediaType: .pdf).get()
        return try await publicationOpener(httpClient: httpClient).open(asset: asset, allowUserInteraction: false).get()
    }

    private func fetch() async throws -> URL {
        let file = FileManager.default.temporaryDirectory.appending(path: "\(pdf.bookID)-\(UUID().uuidString).pdf")
        try await pdf.contents().write(to: file, options: .atomic)
        fetched = file
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

    /// Back in the app: if the reader read on elsewhere meanwhile, moves there rather than
    /// keeping an older page that the next page turn would share over it (ADR 0002).
    func catchUp() async {
        guard hasLanded, let positions, let sharedPositions, let publication = navigator?.publication,
              let newer = try? await positions.catchUp(.pdf, bookID: pdf.bookID, bookFileID: bookFileID, from: sharedPositions),
              case let .pdf(saved) = newer.location, let link = publication.readingOrder.first
        else { return }
        // Already the latest Position, so arriving there isn't new reading.
        page = saved.page
        let locator = Locator(href: link.url(), mediaType: .pdf, locations: .init(fragments: ["page=\(saved.page)"], position: saved.page))
        _ = await navigator?.go(to: locator, options: NavigatorGoOptions(animated: false))
    }

    // MARK: PDFNavigatorDelegate

    func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
        guard let page = locator.locations.page ?? locator.locations.position else { return }
        // Spreads, zooming and showing or hiding the controls report the same page again; only a
        // new page is new reading. PDFKit's swipes don't reach Readium's input observers, so pages
        // can't be told apart by what caused them as EPUB locations are.
        guard page != self.page else { return }
        self.page = page
        record(page, share: hasLanded)
        hasLanded = true
    }

    private func record(_ page: Int, share: Bool) {
        // Matches the web reader, which shares page ÷ page count.
        let throughBook = pageCount.map { Double(page) / Double(max($0, 1)) } ?? 0
        recorder.record(bookFileID: bookFileID, share: share) {
            .pdf(PDFLocation(page: page, throughBook: throughBook))
        } afterSharing: {
            self.pushSoon()
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
        if let fetched { try? FileManager.default.removeItem(at: fetched) }
        fetched = nil
        pushing?.cancel()
        await recorder.finished()
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
