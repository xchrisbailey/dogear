import Foundation

/// An EPUB's spine as its package document lists it, for turning a CFI's spine step into a
/// resource and back (ADR 0004).
///
/// Every itemref counts, including `linear="no"` ones that a reader's reading order leaves out,
/// because CFI spine steps index the package document's elements.
public struct EPUBSpine: Sendable, Equatable {
    struct Item: Sendable, Equatable {
        /// Resolved against the package document, relative to the EPUB's root, percent-encoded.
        var href: String
        /// Path from the package element to the itemref, with ID assertions, e.g. `/6/8[ch2]`.
        var step: String
    }

    let items: [Item]

    /// Reads `META-INF/container.xml`, then the package document it points to. nil if either is
    /// missing or unreadable.
    public nonisolated(nonsending) static func load(reading entry: (String) async -> Data?) async -> EPUBSpine? {
        guard let container = await entry("META-INF/container.xml"),
              let packagePath = PackageParser.rootfile(in: container),
              let package = await entry(packagePath)
        else { return nil }
        return PackageParser.spine(in: package, at: packagePath)
    }

    /// The resource a CFI's spine step points at, or nil when it points outside the spine.
    public func href(of cfi: String) -> String? {
        guard let step = Self.spineStep(of: cfi) else { return nil }
        return items.first { Self.indices(of: $0.step) == step }?.href
    }

    /// The spine step to join in front of an in-resource CFI for `href`, e.g. `/6/8[ch2]`.
    public func step(of href: String) -> String? {
        let wanted = Self.normalized(href)
        return items.first { Self.normalized($0.href) == wanted }?.step
    }

    private static func normalized(_ href: String) -> String {
        let path = href.split(separator: "#", maxSplits: 1).first.map(String.init) ?? href
        return path.removingPercentEncoding ?? path
    }

    /// Step indices before the CFI's first indirection (`!`). ID assertions are ignored, as
    /// foliate's web reader does when they disagree with the index.
    private static func spineStep(of cfi: String) -> [Int]? {
        guard cfi.hasPrefix("epubcfi("), let indirection = unescapedIndex(of: "!", in: cfi) else { return nil }
        return indices(of: String(cfi[cfi.index(cfi.startIndex, offsetBy: 8) ..< indirection]))
    }

    private static func indices(of path: String) -> [Int]? {
        var indices: [Int] = []
        var rest = Substring(path)
        while !rest.isEmpty {
            guard rest.first == "/" else { return nil }
            rest = rest.dropFirst()
            let digits = rest.prefix { $0.isNumber }
            guard let index = Int(digits) else { return nil }
            indices.append(index)
            rest = rest.dropFirst(digits.count)
            if rest.first == "[" {
                guard let close = unescapedIndex(of: "]", in: rest) else { return nil }
                rest = rest[rest.index(after: close)...]
            }
        }
        return indices
    }

    private static func unescapedIndex<S: StringProtocol>(of character: Character, in text: S) -> S.Index? {
        var escaped = false
        for index in text.indices {
            let current = text[index]
            if escaped {
                escaped = false
            } else if current == "^" {
                escaped = true
            } else if current == character {
                return index
            }
        }
        return nil
    }
}

/// Reads the parts of `container.xml` and the package document the CFI mapping needs.
private final class PackageParser: NSObject, XMLParserDelegate {
    private var path: [String] = []
    /// Element children seen so far, per open element.
    private var childCounts: [Int] = [0]
    private var rootfile: String?
    private var manifest: [String: String] = [:]
    private var spineStep: String?
    private var itemrefs: [(idref: String, step: String)] = []

    static func rootfile(in container: Data) -> String? {
        let parser = PackageParser()
        _ = parser.parse(container)
        return parser.rootfile
    }

    static func spine(in package: Data, at packagePath: String) -> EPUBSpine? {
        let parser = PackageParser()
        guard parser.parse(package), let base = URL(string: "epub:///")?.appending(path: packagePath) else { return nil }
        let items = parser.itemrefs.compactMap { itemref -> EPUBSpine.Item? in
            guard let href = parser.manifest[itemref.idref], let url = URL(string: href, relativeTo: base) else { return nil }
            return EPUBSpine.Item(href: String(url.absoluteURL.path(percentEncoded: true).drop { $0 == "/" }), step: itemref.step)
        }
        return items.isEmpty ? nil : EPUBSpine(items: items)
    }

    private func parse(_ data: Data) -> Bool {
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = self
        return parser.parse()
    }

    func parser(
        _ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
        qualifiedName: String?, attributes: [String: String] = [:]
    ) {
        childCounts[childCounts.count - 1] += 1
        // CFI steps number element children with even indices.
        let step = "/\(childCounts[childCounts.count - 1] * 2)" + (attributes["id"].map { "[\(Self.escaped($0))]" } ?? "")
        switch (path, name) {
        case (["container", "rootfiles"], "rootfile") where rootfile == nil:
            rootfile = attributes["full-path"]
        case (["package", "manifest"], "item"):
            if let id = attributes["id"], let href = attributes["href"] { manifest[id] = href }
        case (["package"], "spine"):
            spineStep = step
        case (["package", "spine"], "itemref"):
            if let idref = attributes["idref"], let spineStep { itemrefs.append((idref, spineStep + step)) }
        default:
            break
        }
        path.append(name)
        childCounts.append(0)
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        path.removeLast()
        childCounts.removeLast()
    }

    private static func escaped(_ id: String) -> String {
        id.replacing(/[\^\[\](),;=]/) { "^" + $0.output }
    }
}
