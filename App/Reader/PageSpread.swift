@preconcurrency import ReadiumNavigator

/// Whether paged mode shows one page or two side by side.
///
/// Readium splits this across two preferences: columns for reflowable EPUBs and synthetic
/// spreads for fixed-layout ones, so one choice sets both.
enum PageSpread: CaseIterable {
    /// Two pages when the reader is wider than it is tall and wide enough for them, e.g. an iPad
    /// in landscape, one page otherwise, including a narrow split view.
    case automatic
    case one
    case two

    init(_ preferences: EPUBPreferences) {
        self = switch preferences.columnCount ?? .auto {
        case .auto: .automatic
        case .one: .one
        case .two: .two
        }
    }

    var name: String {
        switch self {
        case .automatic: "Automatic"
        case .one: "One page"
        case .two: "Two pages"
        }
    }

    func apply(to preferences: inout EPUBPreferences) {
        switch self {
        case .automatic:
            preferences.columnCount = .auto
            preferences.spread = .auto
        case .one:
            preferences.columnCount = .one
            preferences.spread = .never
        case .two:
            preferences.columnCount = .two
            preferences.spread = .always
        }
    }
}
