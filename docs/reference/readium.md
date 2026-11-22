# Readium: behaviour Dogear's readers depend on

How Readium opens Grimmory EPUBs and PDFs and how the CFI bridge runs inside its navigator, verified against Readium swift-toolkit 3.11.1 and Grimmory v3.5.0 (simulator, iOS 27.2, Nov 2026).

Source: Readium swift-toolkit 3.11.1 (`git clone --branch 3.11.1 https://github.com/readium/swift-toolkit`), paths relative to `Sources/`. Grimmory paths are from its v3.5.0 source (see `grimmory-api.md`).

## Opening a Server EPUB without a Download

Implementation: `openPublication()` and `openEPUB(in:httpClient:)` in `App/Reader/EPUBReaderModel.swift`, signing in `App/Reader/EPUBRequestSigner.swift` + `Core/Sources/DogearCore/ServerEPUB.swift`.

- `HTTPContainer` (`Shared/Toolkit/HTTP/HTTPContainer.swift`) resolves every entry href against `baseURL`, pointed at `/api/v1/epub/{id}/file/`. The trailing slash matters.
- **A query on `baseURL` is dropped** when Readium resolves relative hrefs, so `bookType=EPUB` and auth go on per request in the `DefaultHTTPClientDelegate` (`willStartRequest`). `DefaultHTTPClient(additionalHeaders:)` would freeze the token at creation, which breaks after a refresh.
- `DefaultHTTPClient` holds its delegate **weakly**: the owner must keep the signer alive.
- Grimmory doesn't serve the `mimetype` entry, so `AssetRetriever` sniffing fails: declare the format (`Format(specifications: .zip, .epub, …)`) and open a `ContainerAsset` directly.
- Open cost (live): 0.2–0.6 s. Readium requests `META-INF/encryption.xml` and both display-options files (404s, ignored), `container.xml`, the OPF and the nav doc.
- `publication.positions()` takes 0.8–2.0 s and fetches **every reading-order resource once** (no HEADs). To avoid that, a wrapping container could report `estimatedLength` from the epub info `manifest[].size` (positions use `archiveEntryLength(pageLength: 1024)`, falling back to `estimatedLength`: `Streamer/Parser/EPUB/Services/EPUBPositionsService.swift` L41–50). Not done; only worth it if open time hurts.
- The entry endpoint ignores `Range` and sends no `Accept-Ranges`; `DefaultHTTPClient` then fails ranged reads with `.rangeNotSupported` (`DefaultHTTPClient.swift` ~L448). HTML/CSS/images are read whole so this doesn't bite; audio/video embedded in an EPUB would.
- `DefaultHTTPClient` uses `URLSessionConfiguration.default`, so `URLCache` honours Grimmory's `Cache-Control: private, max-age=3600`.
- Alternative not taken: `/api/v1/books/{id}/content` (Range-capable zip, no `canDownload`) via `AssetRetriever.retrieve(url:)` would read the ZIP remotely with range requests. Untested; a fallback if the entry endpoint misbehaves for some EPUB.

## Spine vs reading order

- `publication.readingOrder` **omits `linear="no"` itemrefs** (`Streamer/Parser/EPUB/OPFParser.swift` L244–245). A live book had 78 spine itemrefs and a 43-item reading order.
- CFI spine steps index the OPF's element children (all itemrefs), and the prefix is the real path to `<spine>` with `[id]` only where the element has an `id` attribute (foliate builds it with `CFI.fromElements($itemrefs)`: Grimmory `frontend/src/assets/foliate/epub.js` L676, `epubcfi.js` L313). `/6` is only the usual case. Epub info doesn't expose itemref `id`s, so `Core/Sources/DogearCore/EPUBSpine.swift` parses the OPF itself and maps by href, ignoring ID assertions as foliate does when they disagree.
- The default navigator only paginates `readingOrder`. A custom `readingOrder:` init exists but disables positions and `totalProgression` (`EPUB/EPUBNavigatorViewController.swift` ~L278–300). A CFI into a non-linear item falls back to href/percent (`fallbackLocation` in `EPUBReaderModel.swift`).

## MOBI, AZW3 and FB2, converted (ADR 0005)

Implementation: `App/Reader/EPUBConverter.swift`, `App/Reader/Resources/ebook-to-epub.js`, with foliate-js's `mobi.js`, `fb2.js` and `vendor/fflate.js` at commit 675fdaf (the revision Grimmory ships: identical `mobi.js`, `fb2.js` and `epubcfi.js`).

- The converter's web view is never put on screen. A `WKURLSchemeHandler` (`dogear-convert://`) serves its blank page, the modules and the Book file, so ES module imports and the `fetch` are same-origin.
- foliate turns each section and resource into a `blob:` URL; `blob-recorder.js` keeps the Blobs so the converter can write them into the EPUB in place of the URLs. MOBI resources come without a type, so they're told apart by their first bytes.
- Each section keeps the type foliate gave it: KF8 is XHTML (`.xhtml`, `application/xhtml+xml`), MOBI 6 and KF8 that isn't valid XHTML are HTML (`.html`, `text/html`). The same parser then builds the same DOM in Readium as in the web reader's iframe.
- Table of contents entries and links point at an element's existing `id` where it has one, and otherwise at its section: adding an `id` would change CFIs' ID assertions.

## CFI bridge in the navigator

Implementation: `App/Reader/CFIBridge.swift`, `App/Reader/Resources/epubcfi.js` (foliate's, from Grimmory v3.5.0, exports exposed as `window.CFI`), `App/Reader/Resources/cfi-bridge.js` (`window.dogearCFI`). Design: ADR 0004.

- Scripts go in via `navigator(_:setupUserScripts:)` as `WKUserScript(.atDocumentEnd, forMainFrameOnly: true)`; it is called once per spread web view (4 calls seen on open). They run inside `HTTPContainer` resources too.
- **Never a `<script>` element**: it would shift CFI child indices. Readium itself only adds attributes to `<html>`/`<body>` and CSS in `<head>`, so step indices match the raw XHTML.
- `nav.evaluateJavaScript(_:)` (`EPUB/EPUBNavigatorViewController.swift` L931) runs in the **current spread's** web view and fails with `EPUBError.spreadNotLoaded` (a) before the first `locationDidChange` and (b) **right after `go(to:)` returns** to another resource. The bridge waits for the next `locationDidChange`, then retries evaluation briefly.
- Timing: first `locationDidChange` took 15 s in a freshly created simulator (cold WebKit); resolve ~2.2 s cold, 0.8 s warm. Give seam-2 tests generous timeouts.
- Paged progression is `(rect.left + scrollX + 1) / scrollWidth`; scroll mode (`--USER__view == readium-scroll-on`) uses `top`/`scrollHeight`, and the visible-range port maps vertical boxes onto the horizontal axis as foliate's paginator does.
- Generated CFIs are ranges; the Shared position gets `CFI.collapse` of the start. Compare by collapsed start, since range ends depend on the viewport.
- Seam-2 fixture: `AppTests/Fixtures/LighthouseLedger`. The live-library CFI in `app-progress-epub.json` is web-reader output kept only as a decoding fixture.

## Navigator facts

- `navigator(_:locationDidChange:)` gives `locations.progression` (in-resource 0…1), `totalProgression` (book), `position`.
- `go(to:options:)` returns `Bool`; TOC from `publication.tableOfContents()`.
- Same-device resume restores the `Locator` JSON (`jsonString` / `Locator(jsonString:)`), more precise than a CFI.
- `EPUBPreferences` (`Navigator/EPUB/Preferences/EPUBPreferences.swift`) is Codable; `publisherStyles: false` is needed for user typography to apply; `spread` controls iPad two-page; apply with `submitPreferences(_:)`. `nav.editor(of:)` (`Navigator/Preferences/Configurable.swift` L78) gives ranges and steps for controls.
- Readium's `AudioNavigator` exists; Dogear uses AVFoundation directly (`audio.md`).

## PDF

- Readium's PDFKit factory reads a non-file resource **fully into memory** (`Shared/Toolkit/PDF/PDFKit.swift` L84–104, "PDFKit doesn't support streams"), so streaming gains nothing. Without a Download, `App/Reader/PDFReaderModel.swift` fetches `/books/{id}/content?bookType=PDF` into a **temporary file deleted on close**: content that isn't a Download must not persist for offline use (it would be a Download the account may not be allowed).
- PDF Locator: `locations.position` = 1-based page, plus `fragments: ["page=N"]` (`Navigator/PDF/PDFNavigatorViewController.swift` L507–520); resume with both.
- PDFKit swipes don't reach Readium's input observers, so PDF page turns can't be told apart from relocations by input the way EPUB ones are.
- Untested live (no PDF on the test Server).
