import SwiftUI

/// Shared geometry for the expanded HUD.
///
/// The expanded HUD is drawn by two stacked windows: DynamicNotchKit renders the
/// black notch band at the top of the screen, and a separate interactive panel
/// hangs directly beneath it (the notch window is click-through, so all hit
/// testing lives in the panel). For the two to read as ONE surface they must
/// share a width, and the seam between them must be a straight edge.
enum NotchPanelMetrics {
    /// Width of the interactive panel, and the width the notch band expands to.
    static let width: CGFloat = 680

    /// Outward flare where the expanded notch meets the top of the screen.
    static let expandedTopCornerRadius: CGFloat = 15

    /// Zero, deliberately: a rounded bottom edge on the notch band would carve
    /// two curves out of the seam and give the join away.
    static let expandedBottomCornerRadius: CGFloat = 0

    /// Opening: both halves unfurl together. The band is animated by
    /// DynamicNotchKit; the panel is an NSPanel with no appearance animation of
    /// its own, so its CONTENT is masked to a width driven by the same curve.
    static let openDuration: TimeInterval = 0.05
    static let openAnimation: Animation = .snappy(duration: openDuration)

    /// Closing: instant. Once the pointer is gone the HUD is in the way, so there
    /// is nothing to watch. A hair above zero because SwiftUI treats a
    /// zero-duration animation as "no animation" and falls back to the default.
    static let closeAnimation: Animation = .linear(duration: 0.001)

    /// The panel is pulled up by a hair so it overlaps the band instead of merely
    /// abutting it. Both surfaces are opaque black, so the overlap is invisible,
    /// but it guarantees no desktop shows through on a fractional boundary.
    static let seamOverlap: CGFloat = 1

    /// `NotchView` lays the expanded content out inside a horizontal padding of
    /// `topCornerRadius` on each side, so the content must be narrower than the
    /// band by exactly that much to land on `width`.
    static var expandedContentWidth: CGFloat {
        width - (expandedTopCornerRadius * 2)
    }
}

/// Transparent stand-in for the expanded notch content.
///
/// It renders nothing; its only job is to give `NotchView` a width to size the
/// expanded band to, so the band matches the interactive panel hanging below it.
struct NotchExpandedSpacer: View {
    var body: some View {
        Color.clear
            .frame(width: NotchPanelMetrics.expandedContentWidth, height: 0)
    }
}


/// Drives the panel's reveal so it unfurls in step with the notch band.
///
/// The panel window is always full size; only the mask width animates, so the
/// SwiftUI content never reflows mid-flight (a window-resize animation would
/// rewrap every row of text as it grew).
@MainActor
@Observable
final class HUDRevealState {
    var isRevealed = false
}
