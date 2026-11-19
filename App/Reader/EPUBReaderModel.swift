import DogearCore
import Foundation
@preconcurrency import ReadiumNavigator
@preconcurrency import ReadiumShared
@preconcurrency import ReadiumStreamer

/// Opens a Server EPUB in Readium's navigator and keeps the reader's Position on the device.
@Observable
final class EPUBReaderModel: EPUBNavigatorDelegate {
    enum State {
        case opening
        case reading(EPUBNavigatorViewController)
        case failed(String)
    }

    private(set) var state: State = .opening
    private(set) var location: Locator?
    private(set) var tableOfContents: [Link] = []
    /// A problem showing part of the Book file; reading can carry on.
    var problem: String?
    var isShowingControls = true

    var preferences: EPUBPreferences {
        didSet {
            navigator?.submitPreferences(preferences)
            ReadingPreferences.save(preferences)
        }
    }

    private let bookFileID: Int
    private let epub: ServerEPUB
    private let positions: Positions?
    private let signer: EPUBRequestSigner
    // Readium holds its HTTP client delegate weakly; this keeps the signer alive with the client.
    private let httpClient: DefaultHTTPClient
    private var publication: Publication?
    private let pageTurns = DirectionalNavigationAdapter()
    private var recording: Task<Void, Never>?

    init(epub: ServerEPUB, bookFileID: Int, positions: Positions?) {
        self.epub = epub
        self.bookFileID = bookFileID
        self.positions = positions
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
                config: .init(preferences: preferences)
            )
            navigator.delegate = self
            pageTurns.bind(to: navigator)
            state = .reading(navigator)
        } catch {
            state = .failed("Couldn't open this EPUB. Check your connection and try again.")
        }
    }

    /// Reads the EPUB entry by entry from the Server, so no Download (or `canDownload`) is needed.
    private func openPublication() async throws -> Publication {
        guard let baseURL = HTTPURL(url: epub.baseURL) else { throw OpenError.invalidAddress }
        let container = HTTPContainer(client: httpClient, baseURL: baseURL, entries: [])
        // Grimmory doesn't serve the EPUB's `mimetype` entry, so Readium can't sniff the format.
        let format = Format(specifications: .zip, .epub, mediaType: .epub, fileExtension: "epub")
        let opener = PublicationOpener(parser: DefaultPublicationParser(
            httpClient: httpClient,
            assetRetriever: AssetRetriever(httpClient: httpClient),
            pdfFactory: DefaultPDFDocumentFactory()
        ))
        return try await opener.open(asset: .container(ContainerAsset(container: container, format: format)), allowUserInteraction: false).get()
    }

    /// Where to start: the last Position recorded on this device, or the beginning.
    private func resumeLocation(in publication: Publication) async -> Locator? {
        guard case let .epub(saved)? = await positions?.latest(bookFileID: bookFileID)?.location else { return nil }
        if let state = saved.readerState, let locator = try? Locator(jsonString: state) {
            return locator
        }
        // A Position from elsewhere has no reader state; fall back to the Chapter and spot in it.
        guard var locator = await publication.locate(Link(href: saved.href)) else { return nil }
        locator.locations.progression = saved.chapterProgress
        return locator
    }

    func go(to link: Link) async {
        _ = await navigator?.go(to: link, options: NavigatorGoOptions(animated: false))
    }

    /// The Chapter the reader is in: the deepest table of contents entry for the current resource.
    var chapterTitle: String? {
        guard let location else { return nil }
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

    func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
        location = locator
        let epubLocation = EPUBLocation(
            href: locator.href.removingFragment().string,
            chapterProgress: locator.locations.progression ?? 0,
            bookProgress: locator.locations.totalProgression ?? 0,
            readerState: try? locator.jsonString()
        )
        // Chained so a slow save can't land after a newer one and win.
        recording = Task { [previous = recording, positions, bookFileID] in
            await previous?.value
            try? await positions?.record(.epub(epubLocation), bookFileID: bookFileID)
        }
    }

    func navigator(_ navigator: VisualNavigator, didTapAt point: CGPoint) {
        isShowingControls.toggle()
    }

    func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
        problem = "Couldn't show this part of the EPUB. Check your connection."
    }

    private enum OpenError: Error {
        case invalidAddress
    }
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
