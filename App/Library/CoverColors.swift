import DogearCore
import SwiftUI
import UIKit

/// The color each cover reads as, for binding spines and striping cassette labels. Worked out
/// once per cover image and kept across launches, so shelves don't decode covers to draw spines.
@Observable
final class CoverColors {
    private var colors: [String: SpineColor]
    @ObservationIgnored private var loading: Set<String> = []
    @ObservationIgnored private var saving: Task<Void, Never>?

    /// In Caches: iOS may clear it, and the colors can always be worked out again.
    private static let file = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
        .appending(path: "cover-colors.json")

    init() {
        let saved = Self.file.flatMap { try? Data(contentsOf: $0) }
        colors = saved.flatMap { try? JSONDecoder().decode([String: SpineColor].self, from: $0) } ?? [:]
    }

    /// nil until the cover has been looked at, or when the Book has none.
    func color(of cover: Cover?) -> SpineColor? {
        cover.flatMap { colors[Self.key($0)] }
    }

    func load(_ cover: Cover?, from library: Library) async {
        guard let cover else { return }
        let key = Self.key(cover)
        guard colors[key] == nil, !loading.contains(key) else { return }
        loading.insert(key)
        defer { loading.remove(key) }
        guard let data = await library.image(for: cover), let color = await Self.dominantColor(in: data) else { return }
        colors[key] = color
        save()
    }

    /// A changed cover image has a new `updatedOn`, so it's looked at again.
    private static func key(_ cover: Cover) -> String {
        "\(cover.bookID)-\(cover.kind.rawValue)-\(cover.updatedOn)"
    }

    /// Covers arrive in bursts as shelves scroll into view; one write covers a burst.
    private func save() {
        saving?.cancel()
        saving = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let file = Self.file, let data = try? JSONEncoder().encode(colors) else { return }
            try? data.write(to: file, options: .atomic)
        }
    }

    /// Decodes and shrinks the cover off the main actor; Core picks the color from the pixels.
    @concurrent
    nonisolated private static func dominantColor(in data: Data) async -> SpineColor? {
        guard let image = UIImage(data: data)?.cgImage else { return nil }
        let (width, height) = (24, 36)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? SpineColor.dominant(ofRGBA: pixels) : nil
    }
}
