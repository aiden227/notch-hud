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
    /// Both are critically damped springs — see NotchDesign.
    static let openAnimation: Animation = NotchDesign.openSpring

    /// Closing mirrors the opening path rather than hard-cutting.
    static let closeAnimation: Animation = NotchDesign.closeSpring

    /// How long to keep the panel window on screen after asking it to close.
    ///
    /// A spring has no duration — its settle time emerges from the parameters —
    /// so this is the practical window for the critically damped spring above to
    /// finish. Without it the window is ordered out on the same frame the
    /// animation starts, and the close plays on the band only while the panel
    /// simply blinks out: the two halves visibly disagree.
    ///
    /// Generous on purpose. The mask has already retracted to nothing well
    /// before this fires, so extra time costs nothing visually — its only job is
    /// to guarantee the window is never torn down while anything is still on
    /// screen, which is what produced the "shrink, then vanish all at once" pop.
    static let closeSettle: TimeInterval = 0.20

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
