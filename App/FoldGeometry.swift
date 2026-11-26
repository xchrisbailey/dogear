import DogearCore
import SwiftUI

extension GeometryProxy {
    /// The fold crossing this view on iPhone Duo's inner screen, bent or flat, or nil on every
    /// other screen and before iOS 27.1. A view laid out from it is laid out again as the phone
    /// opens, closes or bends, since the region is part of its geometry.
    var fold: Fold? {
        guard #available(iOS 27.1, *) else { return nil }
        // Mirrored in right-to-left layouts, like the stacks laid out from it.
        return reservedRegions(kind: .division, options: .includeInactive).lazy.compactMap { region in
            Fold(
                x: region.frame.minX, y: region.frame.minY, width: region.frame.width, height: region.frame.height,
                viewWidth: size.width, viewHeight: size.height, isBent: region.isActive
            )
        }.first
    }
}
