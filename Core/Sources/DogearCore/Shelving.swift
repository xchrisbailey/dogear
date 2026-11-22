import Foundation

/// How a Book stands on the Library's shelf: what its spine says and how big it is.
///
/// Sizes are in points. A bigger ebook file makes a thicker spine, as more pages would; the
/// height, and the thickness of a Book whose size isn't known, come from the Book's id. Either
/// way a shelf looks uneven like a real one and a Book never changes shape between launches or
/// devices.
public struct Spine: Sendable, Equatable {
    public static let thicknesses: ClosedRange<Double> = 26 ... 46
    public static let heights: ClosedRange<Double> = 160 ... 196
    public static let fontSizes: ClosedRange<Double> = 12 ... 19
    /// Ebook file sizes, in kilobytes, that span thinnest to thickest. A novel as an EPUB is a
    /// few hundred kilobytes and an illustrated book or a PDF tens of megabytes, so thickness
    /// follows the size's order of magnitude.
    public static let fileSizes: ClosedRange<Double> = 150 ... 30000

    /// The Book's title as a spine has room for it.
    public var title: String
    public var thickness: Double
    public var height: Double
    /// Thicker spines carry bigger type.
    public var fontSize: Double
    /// The spine's color when the Book has no cover to take one from.
    public var fallbackColor: SpineColor

    public init(book: Book) {
        title = Self.title(for: book.title)
        let thick = Self.thickness(ofFileSized: Self.ebookSize(of: book)) ?? Self.fraction(of: book.id, salt: 1)
        thickness = Self.thicknesses.lowerBound + (thick * (Self.thicknesses.upperBound - Self.thicknesses.lowerBound)).rounded()
        height = Self.heights.lowerBound
            + (Self.fraction(of: book.id, salt: 2) * (Self.heights.upperBound - Self.heights.lowerBound)).rounded()
        let share = (thickness - Self.thicknesses.lowerBound) / (Self.thicknesses.upperBound - Self.thicknesses.lowerBound)
        fontSize = Self.fontSizes.lowerBound + (share * (Self.fontSizes.upperBound - Self.fontSizes.lowerBound)).rounded()
        fallbackColor = SpineColor.palette[Int(Self.mixed(book.id, salt: 3) % UInt64(SpineColor.palette.count))]
    }

    /// A spine is narrow, so it carries the main title only: no subtitle, no leading article.
    /// "The Odyssey" is "Odyssey"; "Moby-Dick; or, The Whale" is "Moby-Dick".
    public static func title(for title: String) -> String {
        var short = title.trimmingCharacters(in: .whitespaces)
        for separator in [":", ";", " - ", " – ", " — "] {
            if let cut = short.range(of: separator) {
                let main = short[..<cut.lowerBound].trimmingCharacters(in: .whitespaces)
                if !main.isEmpty { short = main }
            }
        }
        for article in ["the ", "an ", "a "] where short.lowercased().hasPrefix(article) {
            let rest = short.dropFirst(article.count).trimmingCharacters(in: .whitespaces)
            if !rest.isEmpty { short = rest }
            break
        }
        return short
    }

    /// The size of the Book's ebook file: the EPUB if it has one, since a PDF or Kindle file of
    /// the same Book is bigger for reasons other than its length.
    static func ebookSize(of book: Book) -> Int? {
        let ebooks = book.files.filter { $0.format != .audiobook && ($0.sizeKB ?? 0) > 0 }
        return (ebooks.first { $0.format == .epub } ?? ebooks.first)?.sizeKB
    }

    /// 0 for the thinnest spine to 1 for the thickest. nil when the size isn't known.
    static func thickness(ofFileSized sizeKB: Int?) -> Double? {
        guard let sizeKB, sizeKB > 0 else { return nil }
        let span = log(fileSizes.upperBound) - log(fileSizes.lowerBound)
        return min(max((log(Double(sizeKB)) - log(fileSizes.lowerBound)) / span, 0), 1)
    }

    /// 0…1, the same for a Book id on every launch (`Hasher` is seeded per process).
    private static func fraction(of id: Int, salt: UInt64) -> Double {
        Double(mixed(id, salt: salt) % 1000) / 999
    }

    /// SplitMix64.
    private static func mixed(_ id: Int, salt: UInt64) -> UInt64 {
        var z = UInt64(bitPattern: Int64(id)) &+ salt &* 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// An sRGB color, components 0…1, for spines and cassette labels.
public struct SpineColor: Sendable, Hashable, Codable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Gold foil lettering, for dark spines.
    public static let foil = SpineColor(red: 0.945, green: 0.827, blue: 0.541)
    /// Dark ink lettering, for light spines.
    public static let ink = SpineColor(red: 0.165, green: 0.114, blue: 0.031)
    /// Lettering must stay readable on whatever a cover turns out to be (WCAG AA for text).
    public static let readableContrast = 4.5

    /// Cloth colors for Books without a cover.
    public static let palette: [SpineColor] = [
        SpineColor(red: 0.427, green: 0.122, blue: 0.133), // oxblood
        SpineColor(red: 0.122, green: 0.200, blue: 0.329), // navy
        SpineColor(red: 0.184, green: 0.353, blue: 0.227), // forest
        SpineColor(red: 0.294, green: 0.165, blue: 0.310), // plum
        SpineColor(red: 0.239, green: 0.310, blue: 0.388), // slate
        SpineColor(red: 0.353, green: 0.086, blue: 0.188), // claret
        SpineColor(red: 0.137, green: 0.149, blue: 0.169), // charcoal
        SpineColor(red: 0.431, green: 0.243, blue: 0.118), // tan
    ]

    /// WCAG relative luminance.
    public var luminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    public func contrast(with other: SpineColor) -> Double {
        let (light, dark) = (max(luminance, other.luminance), min(luminance, other.luminance))
        return (light + 0.05) / (dark + 0.05)
    }

    /// The color to bind a spine in and the lettering to stamp on it, given the cover's color.
    /// Light covers keep their color under ink; the rest are darkened until foil reads on them.
    public var shelved: (spine: SpineColor, lettering: SpineColor) {
        if luminance > 0.5 { return (self, .ink) }
        var spine = self
        while spine.contrast(with: .foil) < Self.readableContrast {
            spine = SpineColor(red: spine.red * 0.9, green: spine.green * 0.9, blue: spine.blue * 0.9)
        }
        return (spine, .foil)
    }

    /// The color a cover reads as: its most common color, leaning towards saturated ones so a
    /// red cover with white type reads as red. `rgba` is 8-bit RGBA pixels; nil without any.
    public static func dominant(ofRGBA rgba: [UInt8]) -> SpineColor? {
        struct Bucket {
            var weight = 0.0
            var red = 0.0
            var green = 0.0
            var blue = 0.0
        }
        var buckets: [Int: Bucket] = [:]
        for pixel in stride(from: 0, to: rgba.count - 3, by: 4) where rgba[pixel + 3] > 127 {
            let (r, g, b) = (Double(rgba[pixel]) / 255, Double(rgba[pixel + 1]) / 255, Double(rgba[pixel + 2]) / 255)
            let saturation = max(r, g, b) - min(r, g, b)
            let weight = 0.25 + saturation
            // 3 bits a channel: close shades count as one color.
            let key = Int(rgba[pixel] >> 5) << 6 | Int(rgba[pixel + 1] >> 5) << 3 | Int(rgba[pixel + 2] >> 5)
            var bucket = buckets[key, default: Bucket()]
            bucket.weight += weight
            bucket.red += r * weight
            bucket.green += g * weight
            bucket.blue += b * weight
            buckets[key] = bucket
        }
        // Ties break on the key so the same cover always gives the same color.
        guard let top = buckets.max(by: { ($0.value.weight, $0.key) < ($1.value.weight, $1.key) })?.value else { return nil }
        return SpineColor(red: top.red / top.weight, green: top.green / top.weight, blue: top.blue / top.weight)
    }
}

/// Fills shelves left to right, starting a new shelf when the next spine won't fit.
public enum Shelves {
    /// The spines on each shelf, as ranges into `thicknesses`. A spine wider than a shelf gets
    /// one to itself.
    public static func fill(thicknesses: [Double], shelfWidth: Double, spacing: Double) -> [Range<Int>] {
        var shelves: [Range<Int>] = []
        var start = 0
        var used = 0.0
        for (index, thickness) in thicknesses.enumerated() {
            let needed = index == start ? thickness : used + spacing + thickness
            if needed > shelfWidth, index > start {
                shelves.append(start ..< index)
                start = index
                used = thickness
            } else {
                used = needed
            }
        }
        if start < thicknesses.count { shelves.append(start ..< thicknesses.count) }
        return shelves
    }
}

/// A cassette's two reels showing how far through an audiobook the listener is: tape moves from
/// the supply reel (left) to the take-up reel (right).
public struct TapeReels: Sendable, Equatable {
    /// Radii of the tape wound on each reel, between `hub` and `full`.
    public var supply: Double
    public var takeUp: Double

    /// Tape has a fixed thickness, so the wound area, not the radius, is proportional to time.
    public init(throughBook: Double, hub: Double, full: Double) {
        let through = min(max(throughBook, 0), 1)
        func radius(_ share: Double) -> Double { (hub * hub + share * (full * full - hub * hub)).squareRoot() }
        supply = radius(1 - through)
        takeUp = radius(through)
    }
}
