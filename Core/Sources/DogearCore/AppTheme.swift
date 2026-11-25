import Foundation

/// The look of the whole app: the Library, the catalog card, the readers' chrome and the Pocket
/// Player. Chosen under Settings → Appearance, and independent of the reader's page color.
public enum AppTheme: String, Sendable, CaseIterable {
    /// Warm paper above a dark walnut bookcase, with oxblood controls.
    case walnut
    /// Pale oak and cream in daylight, with moss controls.
    case oak
    /// Bottle-green book cloth, cream labels and rust controls.
    case bookcloth

    public static let standard = AppTheme.walnut

    /// From what the device saved. Nothing saved, or a theme an older or newer Dogear knew, is
    /// the standard one.
    public init(stored: String?) {
        self = stored.flatMap(Self.init(rawValue:)) ?? .standard
    }

    public var name: String {
        switch self {
        case .walnut: "Walnut & Paper"
        case .oak: "Oak & Daylight"
        case .bookcloth: "Bookcloth & Tape"
        }
    }

    /// Whether the canvas behind the navigation bar is dark, so its glyphs are light.
    public var hasDarkCanvas: Bool { self == .bookcloth }
}
