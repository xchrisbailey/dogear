import DogearCore
import Foundation
@preconcurrency import ReadiumNavigator
@preconcurrency import ReadiumShared
@preconcurrency import ReadiumStreamer
import WebKit

/// Opens a Server EPUB, or its Download, in Readium's navigator, keeps the reader's Position on the device and
/// shares it with Grimmory's web reader. MOBI, AZW3 and FB2 Book files open here too, converted
/// to an EPUB first (ADR 0005).
@Observable
final class EPUBReaderModel: EPUBNavigatorDelegate {
    /// Where the EPUB comes from.
    enum Source {
        /// Read entry by entry from the Server.
        case server
        /// A Download's file.
        case download(URL)
        /// A MOBI, AZW3 or FB2 in `format`, made into an EPUB from the bytes `book` gives.
        case converted(format: BookFile.Format, book: () async throws -> Data)
    }

    enum State {
        case opening
        case reading(EPUBNavigatorViewController)
        case failed(String)
    }

    private(set) var state: State = .opening
    private(set) var location: Locator?
    /// The location the folio shows. Readium moves before a turning page has landed, and moves
    /// back if the page is put down again, so the folio waits for the page.
    private(set) var shownLocation: Locator?
    /// A page is in the air or in the reader's hand.
    private var isTurningPage = false
    private(set) var tableOfContents: [Link] = []
    /// A problem showing part of the Book file; reading can carry on.
    var problem: String?
    var isShowingControls = true

    var preferences: EPUBPreferences {
        didSet {
            moves.relocated()
            navigator?.submitPreferences(preferences.onPaper)
            ReadingPreferences.save(preferences)
        }
    }

    private let bookFileID: Int
    private let epub: ServerEPUB
    private let source: Source
    /// A converted EPUB, deleted on close: only Downloads keep Book content on the device.
    private var converted: URL?
    private let positions: Positions?
    private let sharedPositions: SharedPositions?
    private let signer: EPUBRequestSigner
    // Readium holds its HTTP client delegate weakly; this keeps the signer alive with the client.
    private let httpClient: DefaultHTTPClient
    private var publication: Publication?
    private let recorder: PositionRecorder
    private var moves = ReaderMoves()
    private var bridge: CFIBridge?
    /// A Shared position's CFI to land on once the navigator can run scripts.
    private var pendingCFI: String?
    /// Until the reader has landed where they left off, locations aren't new reading.
    private var hasLanded = false
    private var landing: Task<Void, Never>?
    private var pushing: Task<Void, Never>?
    private static let pushDelay = Duration.seconds(3)

    init(epub: ServerEPUB, source: Source, bookFileID: Int, positions: Positions?, sharedPositions: SharedPositions?) {
        self.epub = epub
        self.source = source
        self.bookFileID = bookFileID
        self.positions = positions
        self.sharedPositions = sharedPositions
        recorder = PositionRecorder(bookID: epub.bookID, positions: positions, sharedPositions: sharedPositions)
        signer = EPUBRequestSigner(epub: epub)
        httpClient = DefaultHTTPClient(delegate: signer)
        preferences = ReadingPreferences.load()
    }

    private var navigator: EPUBNavigatorViewController? {
        if case let .reading(navigator) = state { navigator } else { nil }
    }

    func open() async {
        guard case .opening = state else { return }
        do {
            let publication = try await openPublication()
            self.publication = publication
            tableOfContents = (try? await publication.tableOfContents().get()) ?? []
            let navigator = try EPUBNavigatorViewController(
                publication: publication,
                initialLocation: await resumeLocation(in: publication),
                config: .init(preferences: preferences.onPaper)
            )
            if let spine = await CFIBridge.spine(of: publication) {
                bridge = CFIBridge(navigator: navigator, publication: publication, spine: spine)
            }
            navigator.delegate = self
            navigator.addObserver(ReaderInput { [weak self] in self?.moves.readerMoved() })
            state = .reading(navigator)
        } catch let error as RequestError where error == .forbidden || error == .notFound {
            state = .failed(error.errorDescription ?? "Couldn't open this Book.")
        } catch EPUBConverter.Failure.protected {
            state = .failed("This \(formatName) is locked with DRM by the store it came from, so only that store's apps can open it.")
        } catch EPUBConverter.Failure.unreadable {
            state = .failed("Couldn't read this \(formatName). The file may be damaged.")
        } catch {
            state = .failed("Couldn't open this \(formatName). Check your connection and try again.")
        }
    }

    private var formatName: String {
        if case let .converted(format, _) = source { format.name } else { "EPUB" }
    }

    /// Without a Download, reads the EPUB entry by entry from the Server, so `canDownload` isn't needed.
    private func openPublication() async throws -> Publication {
        switch source {
        case .server:
            guard let baseURL = HTTPURL(url: epub.baseURL) else { throw OpenError.invalidAddress }
            return try await openEPUB(in: HTTPContainer(client: httpClient, baseURL: baseURL, entries: []), httpClient: httpClient)
        case let .download(file):
            return try await openFile(file)
        case let .converted(format, book):
            let data = try await book()
            let file = FileManager.default.temporaryDirectory.appending(path: "\(epub.bookID)-\(UUID().uuidString).epub")
            try await EPUBConverter.epub(from: data, format: format).write(to: file, options: .atomic)
            converted = file
            return try await openFile(file)
        }
    }

    private func openFile(_ file: URL) async throws -> Publication {
        guard let file = FileURL(url: file) else { throw OpenError.invalidAddress }
        let asset = try await AssetRetriever(httpClient: httpClient).retrieve(url: file, mediaType: .epub).get()
        return try await publicationOpener(httpClient: httpClient).open(asset: asset, allowUserInteraction: false).get()
    }

    /// Where to start: the newer of this device's Position and the Shared position (ADR 0002).
    /// Offline, only the device's.
    private func resumeLocation(in publication: Publication) async -> Locator? {
        let local = await positions?.latest(bookFileID: bookFileID)
        let shared = try? await sharedPositions?.latest(.epub, bookID: epub.bookID, bookFileID: bookFileID)
        let newest = [local, shared].compactMap(\.self).max { $0.recordedAt < $1.recordedAt }
        guard case let .epub(saved)? = newest?.location else { return nil }
        if let state = saved.readerState, let locator = try? Locator(jsonString: state) {
            return locator
        }
        // From elsewhere: land on the CFI once the page can run scripts. Until then, and if it
        // doesn't resolve, the fallback.
        pendingCFI = saved.cfi
        return await fallbackLocation(for: saved, in: publication)
    }

    /// Where a Position without this device's reader state lands when its CFI doesn't resolve:
    /// the Chapter and spot in it, then the spot in the whole Book file.
    private func fallbackLocation(for saved: EPUBLocation, in publication: Publication) async -> Locator? {
        if let href = AnyURL(string: saved.href), let link = publication.readingOrder.firstWithHREF(href),
           var locator = await publication.locate(link) {
            locator.locations.progression = saved.throughChapter
            return locator
        }
        return await publication.locate(progression: saved.throughBook)
    }

    func go(to link: Link) async {
        moves.readerMoved()
        _ = await navigator?.go(to: link, options: NavigatorGoOptions(animated: false))
    }

    /// A right-to-left Book has its spine on the right.
    var isRightToLeft: Bool {
        navigator?.settings.readingProgression == .rtl
    }

    /// Whether a reader `size` big shows two pages with the spine between them.
    func showsTwoPages(in size: CGSize, isWide: Bool) -> Bool {
        guard let settings = navigator?.settings, !settings.scroll else { return false }
        return switch settings.columnCount {
        case .two: true
        case .one: false
        case .auto: isWide && size.width > size.height
        }
    }

    /// How a page turn is shown, for a reader `size` big. Two pages show side by side when asked
    /// for, or by themselves on a wide, landscape reader.
    func turnStyle(in size: CGSize, isWide: Bool, reduceMotion: Bool) -> PageTurnStyle {
        guard let navigator else { return .none }
        return PageTurnStyle(
            scrolls: navigator.settings.scroll, pagesSideBySide: showsTwoPages(in: size, isWide: isWide),
            fixedLayout: publication?.metadata.layout == .fixed, reduceMotion: reduceMotion
        )
    }

    /// The page is being laid out again: its size changed or the app came back.
    func relocated() {
        moves.relocated()
    }

    /// Back in the app: if the reader read on elsewhere meanwhile, moves there rather than
    /// keeping an older spot that the next page turn would share over it (ADR 0002).
    func catchUp() async {
        // Readium lays the page out again on becoming active.
        moves.relocated()
        guard hasLanded, let positions, let sharedPositions, let publication,
              let newer = try? await positions.catchUp(.epub, bookID: epub.bookID, bookFileID: bookFileID, from: sharedPositions),
              case let .epub(saved) = newer.location,
              // The reader carried on here while the Server was asked.
              !moves.isReading
        else { return }
        if let cfi = saved.cfi, let bridge, await bridge.go(to: cfi) { return }
        if let locator = await fallbackLocation(for: saved, in: publication) {
            _ = await navigator?.go(to: locator, options: NavigatorGoOptions(animated: false))
        }
    }

    /// Follows a page off the book, so the folio changes when the page lands and not before.
    func pageMoved(_ lift: PageLift) {
        switch lift {
        case .lifted:
            isTurningPage = true
        case .turned:
            isTurningPage = false
            shownLocation = location
        case .putBack:
            // Readium may not have reported moving back yet, so `location` can still be the
            // page that was let go of. The folio already shows the page put back.
            isTurningPage = false
        }
    }

    /// The Chapter the reader is in: the deepest table of contents entry for the current resource.
    var chapterTitle: String? {
        guard let location = shownLocation else { return nil }
        func find(_ links: [Link]) -> String? {
            for link in links {
                if let title = find(link.children) { return title }
                if link.url().removingFragment().isEquivalentTo(location.href.removingFragment()) { return link.title }
            }
            return nil
        }
        return find(tableOfContents) ?? location.title
    }

    // MARK: EPUBNavigatorDelegate

    func navigator(_ navigator: EPUBNavigatorViewController, setupUserScripts userContentController: WKUserContentController) {
        for script in CFIBridge.userScripts { userContentController.addUserScript(script) }
    }

    func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
        location = locator
        if !isTurningPage { shownLocation = locator }
        bridge?.locationDidChange()
        guard hasLanded else {
            if landing == nil { landing = Task { await land() } }
            return
        }
        guard moves.isReading else { return }
        record(locator, share: true)
    }

    /// Scripts only run once the navigator has shown its first page, so a Shared position's CFI
    /// is resolved from there. Where the reader lands is recorded but not shared: it's where
    /// they already were. Locations after it are recorded once the reader moves.
    private func land() async {
        if let bridge, let cfi = pendingCFI {
            // If it doesn't resolve, the reader stays on the fallback they opened at.
            _ = await bridge.go(to: cfi)
        }
        pendingCFI = nil
        hasLanded = true
        if let location { record(location, share: false) }
    }

    private func record(_ locator: Locator, share: Bool) {
        recorder.record(bookFileID: bookFileID, share: share) { [bridge] in
            .epub(EPUBLocation(
                href: locator.href.removingFragment().string,
                throughChapter: locator.locations.progression ?? 0,
                throughBook: locator.locations.totalProgression ?? 0,
                cfi: await bridge?.currentPosition(),
                readerState: try? locator.jsonString()
            ))
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
        if let converted { try? FileManager.default.removeItem(at: converted) }
        converted = nil
        pushing?.cancel()
        await recorder.finished()
        guard let positions, let sharedPositions else { return }
        try? await positions.flushOutbox(to: sharedPositions)
    }

    /// A tap on the middle of the page. The tap itself counted as the reader moving, but it
    /// took them nowhere.
    func toggleControls() {
        moves.relocated()
        isShowingControls.toggle()
    }

    func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
        problem = "Couldn't show this part of the EPUB. Check your connection."
    }

    private enum OpenError: Error {
        case invalidAddress
    }
}

/// Reports every touch and key press on the page: a page turn, scroll or swipe starts with one,
/// while a relocation never does.
final class ReaderInput: InputObserving {
    private let onInput: () -> Void

    init(onInput: @escaping () -> Void) {
        self.onInput = onInput
    }

    func didReceive(_ event: PointerEvent) async -> Bool {
        if event.phase == .down { onInput() }
        return false
    }

    func didReceive(_ event: KeyEvent) async -> Bool {
        if event.phase == .down { onInput() }
        return false
    }
}

/// Opens an EPUB from `container` without sniffing: Grimmory doesn't serve the `mimetype` entry.
func openEPUB(in container: Container, httpClient: HTTPClient) async throws -> Publication {
    let format = Format(specifications: .zip, .epub, mediaType: .epub, fileExtension: "epub")
    return try await publicationOpener(httpClient: httpClient).open(asset: .container(ContainerAsset(container: container, format: format)), allowUserInteraction: false).get()
}

func publicationOpener(httpClient: HTTPClient) -> PublicationOpener {
    PublicationOpener(parser: DefaultPublicationParser(
        httpClient: httpClient,
        assetRetriever: AssetRetriever(httpClient: httpClient),
        pdfFactory: DefaultPDFDocumentFactory()
    ))
}

/// The reader's typography, theme and layout, shared by every EPUB on the device.
enum ReadingPreferences {
    private static let key = "reader.epubPreferences"

    static func load() -> EPUBPreferences {
        guard let data = UserDefaults.standard.data(forKey: key),
              let preferences = try? JSONDecoder().decode(EPUBPreferences.self, from: data)
        else { return EPUBPreferences(theme: .light) }
        return preferences
    }

    static func save(_ preferences: EPUBPreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
