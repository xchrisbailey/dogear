import DogearCore
import Testing

/// The app theme chosen under Settings → Appearance.
struct AppThemeTests {
    @Test func savedThemeComesBack() {
        for theme in AppTheme.allCases {
            #expect(AppTheme(stored: theme.rawValue) == theme)
        }
    }

    /// Nothing saved yet, a theme this Dogear doesn't know, or a Player skin name from the
    /// version that had skins, shows Walnut & Paper.
    @Test(arguments: [nil, "", "hifi", "Walnut"] as [String?])
    func unknownThemeFallsBackToWalnut(stored: String?) {
        #expect(AppTheme(stored: stored) == .walnut)
    }

    @Test func threeThemesWithReadableNames() {
        #expect(AppTheme.allCases.map(\.name) == ["Walnut & Paper", "Oak & Daylight", "Bookcloth & Tape"])
        #expect(AppTheme.allCases.filter(\.hasDarkCanvas) == [.bookcloth])
    }
}
