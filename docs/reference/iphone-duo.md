# iPhone Duo

Apple's foldable iPhone. Checked on Xcode 27.2 (27B52) with the iPhone Duo simulator (runtime iOS 27.2, `SimRuntime.iOS-27-2-iPhone19-4`) and the iPhoneOS27.2 SDK, 2026-11-26.

## Screens

| State | Points | Size classes (reported by third parties) |
| --- | --- | --- |
| Folded, outer screen | 466 × 678 (1398 × 2034 px, @3x) | compact width |
| Open, inner screen, landscape (its default when opened) | 951 × 669 | regular width, regular height |
| Open, inner screen, portrait | 669 × 951 | regular width, regular height |

- `userInterfaceIdiom` is still `.phone`, so the iPhone orientation keys in `project.yml` apply.
- An app built with the iOS 27.1 SDK or later fills both screens edge to edge. Older SDKs are letterboxed. Dogear built with 27.2 fills the inner screen with no black bars.
- Folded, the status bar is a column on one side (the "vertical bar"), and navigation and toolbar items can move into it. `toolbarVerticalBehavior(.disabled)` opts out; `\.toolbarVerticalEdge` says which side it is on.

## The fold

- `GeometryProxy.reservedRegions(kind: .division, options: .includeInactive)` (iOS 27.1) gives the crease as a `ReservedRegion`: `frame` in the view's coordinates (margins for interactive content included), `isActive` true while the phone is partly open. Without `.includeInactive` it's only returned while bent. UIKit: `UIView.reservedRegions(kind:options:)`.
- `.occlusion` regions are the cameras.
- `onHingeChange { old, new in }` gives `DeviceHingeContext.hinge` (`status` closed / partiallyOpen / fullyOpen, and `angle`), nil without a hinge. Apple describes hinge data as for effects and input; lay out from the reserved regions.
- Dogear reads the division region through `GeometryProxy.fold` (`App/FoldGeometry.swift`) into `Fold` (Core), and `PlayerArrangement` decides the Pocket Player's layout from it.
- `ArrangementView` (iOS 27.1) splits primary and secondary content around the fold automatically. Don't nest a `NavigationSplitView` in it or put it in a `List` or `ScrollView`.

## Simulator

- The device type is "iPhone Duo". It runs in Device Hub (`Xcode.app/Contents/Applications/DeviceHub.app`), which has the fold (closed, open, partly open) and rotate controls; there is no `simctl` command for the hinge.
- Screenshots: `xcrun simctl io <udid> screenshot --display=primary` is the outer screen, `--display=primary-1` the inner. Only the awake screen renders.
