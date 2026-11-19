import DogearCore
import Foundation
@preconcurrency import ReadiumNavigator
@preconcurrency import ReadiumShared
import WebKit

/// Resolves and writes the CFIs Grimmory's web reader uses, by running foliate's `epubcfi.js`
/// inside Readium's EPUB navigator (ADR 0004).
///
/// The navigator's delegate must add `userScripts` in `setupUserScripts` and forward every
/// `locationDidChange` to `locationDidChange()`.
final class CFIBridge {
    private let navigator: EPUBNavigatorViewController
    private let publication: Publication
    private let spine: EPUBSpine
    private var locationChanges = 0

    init(navigator: EPUBNavigatorViewController, publication: Publication, spine: EPUBSpine) {
        self.navigator = navigator
        self.publication = publication
        self.spine = spine
    }

    /// The spine as the package document lists it; Readium's reading order drops `linear="no"`
    /// items, so it can't be used to count CFI spine steps.
    static func spine(of publication: Publication) async -> EPUBSpine? {
        await EPUBSpine.load { entry in
            guard let url = AnyURL(string: entry) else { return nil }
            return try? await publication.get(url)?.read().get()
        }
    }

    /// Added as user scripts rather than `<script>` elements, which would shift CFI step indices.
    static let userScripts: [WKUserScript] = ["epubcfi", "cfi-bridge"].compactMap { name in
        guard let url = Bundle.main.url(forResource: name, withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        return WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }

    func locationDidChange() {
        locationChanges += 1
    }

    /// Shows the page holding the CFI's start. false when it can't be resolved here, e.g. it points
    /// at a resource outside the reading order or at a node this EPUB doesn't have.
    func go(to cfi: String) async -> Bool {
        guard let href = spine.href(of: cfi), let url = AnyURL(string: href),
              let link = publication.readingOrder.firstWithHREF(url),
              var locator = await publication.locate(link)
        else { return false }
        if navigator.currentLocation?.href.isEquivalentTo(locator.href) != true {
            await whenLocationChanges { _ = await self.navigator.go(to: link, options: NavigatorGoOptions(animated: false)) }
        }
        guard let progression = await evaluate("dogearCFI.progression(\(Self.literal(cfi)))") as? Double,
              progression.isFinite
        else { return false }
        locator.locations.progression = min(max(progression, 0), 1)
        await whenLocationChanges { _ = await self.navigator.go(to: locator, options: NavigatorGoOptions(animated: false)) }
        return true
    }

    /// The visible range as a CFI, e.g. `epubcfi(/6/8[ch2]!/4/2,/1:0,/9/1:12)`.
    func visibleRange() async -> String? {
        guard let href = navigator.currentLocation?.href, let step = spine.step(of: href.string) else { return nil }
        return await evaluate("dogearCFI.visible(\(Self.literal(step)))") as? String
    }

    /// The point CFI of the start of the visible range: what the Shared position records.
    func currentPosition() async -> String? {
        guard let range = await visibleRange() else { return nil }
        return await evaluate("dogearCFI.collapse(\(Self.literal(range)))") as? String
    }

    /// Compares by collapsed start: range ends depend on the viewport.
    func isSameStart(_ a: String, _ b: String) async -> Bool {
        await evaluate("dogearCFI.sameStart(\(Self.literal(a)), \(Self.literal(b)))") as? Bool == true
    }

    /// Runs `script` in the current spread. It fails while a resource is still loading, so it's retried briefly.
    func evaluate(_ script: String) async -> Any? {
        for _ in 0 ..< 20 {
            if case let .success(value) = await navigator.evaluateJavaScript(script) {
                return value is NSNull ? nil : value
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }

    /// Runs `move` and waits for the navigator to report the new location, which is when its page
    /// can run scripts again. Moving within the current page reports nothing, hence the time limit.
    private func whenLocationChanges(_ move: () async -> Void) async {
        let before = locationChanges
        await move()
        for _ in 0 ..< 60 where locationChanges == before {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// `text` as a JavaScript string literal.
    static func literal(_ text: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [text])) ?? Data("[\"\"]".utf8)
        return String(decoding: data.dropFirst().dropLast(), as: UTF8.self)
    }
}
