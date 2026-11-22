import DogearCore
import Foundation
import WebKit

/// Converts a MOBI, AZW3 or FB2 Book file into an EPUB for the EPUB reader (ADR 0005), with the
/// foliate-js parser Grimmory's web reader uses, run by `ebook-to-epub.js` in a web view that's
/// never shown. The EPUB's CFIs match the web reader's for the same text.
final class EPUBConverter: NSObject, WKNavigationDelegate {
    enum Failure: Error {
        /// DRM-locked: no reader outside the store it came from can open it.
        case protected
        case unreadable
    }

    /// The EPUB made from `book`, a Book file in `format`.
    static func epub(from book: Data, format: BookFile.Format) async throws(Failure) -> Data {
        let converter = EPUBConverter(book: book, fileName: "book.\(format.rawValue)")
        return try await converter.convert()
    }

    private static let scheme = "dogear-convert"
    private static let scripts = ["ebook-to-epub", "blob-recorder", "mobi", "fb2", "fflate"]

    private let book: Data
    private let fileName: String
    private var loading: CheckedContinuation<Void, Never>?

    private init(book: Data, fileName: String) {
        self.book = book
        self.fileName = fileName
    }

    private func convert() async throws(Failure) -> Data {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        // The page, the scripts and the Book file all come from this handler, so the module
        // imports and the fetch are same-origin and nothing touches the network.
        let handler = SchemeHandler(book: book, fileName: fileName, scripts: Self.scripts)
        configuration.setURLSchemeHandler(handler, forURLScheme: Self.scheme)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        await withCheckedContinuation { continuation in
            loading = continuation
            webView.load(URLRequest(url: URL(string: "\(Self.scheme)://book/index.html")!))
        }
        let answer = try? await webView.callAsyncJavaScript(
            "return await (await import('./ebook-to-epub.js')).convertFetched(name)",
            arguments: ["name": fileName],
            contentWorld: .page
        ) as? [String: Any]
        if let base64 = answer?["epub"] as? String, let epub = Data(base64Encoded: base64) { return epub }
        throw answer?["failure"] as? String == "protected" ? .protected : .unreadable
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishLoading()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        finishLoading()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        finishLoading()
    }

    /// A page that failed to load makes the script call fail, which reports it as unreadable.
    private func finishLoading() {
        loading?.resume()
        loading = nil
    }
}

/// Serves the converter's empty page, its scripts from the app bundle, and the Book file.
private final class SchemeHandler: NSObject, WKURLSchemeHandler {
    private let book: Data
    private let fileName: String
    private let scripts: [String]

    init(book: Data, fileName: String, scripts: [String]) {
        self.book = book
        self.fileName = fileName
        self.scripts = scripts
    }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        let name = url.lastPathComponent
        let body: (Data, String)?
        if name == "index.html" {
            body = (Data("<!doctype html><meta charset=\"utf-8\">".utf8), "text/html")
        } else if name == fileName {
            body = (book, "application/octet-stream")
        } else if name.hasSuffix(".js"), scripts.contains(String(name.dropLast(3))),
                  let file = Bundle.main.url(forResource: String(name.dropLast(3)), withExtension: "js"),
                  let script = try? Data(contentsOf: file) {
            body = (script, "text/javascript")
        } else {
            body = nil
        }
        guard let (data, type) = body else {
            task.didReceive(HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!)
            task.didFinish()
            return
        }
        let headers = ["Content-Type": type, "Content-Length": String(data.count)]
        task.didReceive(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: headers)!)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}
}
