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

    /// The interactive panel is an NSPanel shown with `orderFront` — it has no
    /// appearance animation and cannot easily be given one without the SwiftUI
    /// content reflowing mid-flight. So the notch band is driven at the same
    /// rate: near-instant. A non-zero duration is used because SwiftUI treats a
    /// zero-duration animation as "no animation" and falls back to the default.
    static let transitionAnimation: Animation = .linear(duration: 0.01)

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
