import SwiftUI

/// Closes a full-screen view pulled down past its top, the way a sheet is swiped away. On a
/// scroll view, so the pull is its overscroll and scrolling the content still works.
struct PullsDownToClose: ViewModifier {
    let close: () -> Void

    /// How far past the top counts as a pull rather than a bounce.
    private static let distance: CGFloat = 90

    func body(content: Content) -> some View {
        let distance = Self.distance
        return content
            .scrollBounceBehavior(.always, axes: .vertical)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top < -distance
            } action: { _, pulled in
                if pulled { close() }
            }
    }
}
