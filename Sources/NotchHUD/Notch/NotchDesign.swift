import SwiftUI

/// Design tokens for the HUD surface, following Apple's fluid-interface guidance.
enum NotchDesign {
    // MARK: - Motion
    //
    // Apple parameterises springs as damping ratio + response rather than
    // mass/stiffness/damping. Damping 1.0 is critically damped: it reaches the
    // target without overshoot. Bounce is reserved for momentum-driven gestures
    // (a flick, a throw) — this panel appears from a hover, carries no momentum,
    // so overshoot here would read as decoration rather than physics.
    //
    // `.snappy` was previously used, which carries a small built-in bounce.

    /// Opening. Response is the time to approach the target, not a duration.
    static let openSpring = Animation.spring(response: 0.05, dampingFraction: 1.0)

    /// Closing mirrors the opening path and rate. "If something disappears one
    /// way, we expect it to emerge from where it came" — a hard cut on exit
    /// breaks that symmetry and cannot be interrupted mid-flight.
    static let closeSpring = Animation.spring(response: 0.05, dampingFraction: 1.0)

    /// Press feedback. Fast enough to feel like the surface answered the finger.
    static let pressSpring = Animation.spring(response: 0.12, dampingFraction: 1.0)

    /// Reduced motion: no travel, just a short cross-fade.
    static let reducedMotion = Animation.easeOut(duration: 0.12)

    // MARK: - Typography
    //
    // Tracking is size-specific — a single letter-spacing value is wrong
    // somewhere. Small text needs slightly positive tracking to stay legible;
    // large text needs negative tracking because letters read as drifting apart
    // as they grow.

    static func tracking(forSize size: CGFloat) -> CGFloat {
        switch size {
        case ..<10: 0.35
        case ..<12: 0.25
        case ..<14: 0.10
        default: -0.20
        }
    }

    // MARK: - Foreground levels
    //
    // Text over a dark surface needs more contrast than flat mid-grey. These are
    // deliberate levels rather than ad-hoc opacities, so hierarchy stays legible
    // and every value is defensible.

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.72)
    static let textTertiary = Color.white.opacity(0.58)
    static let textQuaternary = Color.white.opacity(0.44)

    /// Increased-contrast variants, used when the system asks for more contrast.
    static let textSecondaryHC = Color.white.opacity(0.90)
    static let textTertiaryHC = Color.white.opacity(0.80)
    static let textQuaternaryHC = Color.white.opacity(0.70)

    // MARK: - Surfaces

    /// Opaque black, matching the notch band above.
    ///
    /// Deliberately NOT a translucent material: the physical notch is a real
    /// black cutout, and the expanded surface has to read as the same object
    /// growing out of it. Translucency would separate them into two things.
    static let surface = Color.black

    static let rowFill = Color.white.opacity(0.05)
    static let rowFillHover = Color.white.opacity(0.10)
    static let rowFillPressed = Color.white.opacity(0.16)
}

/// Apple's first rule of response: feedback lands on press, not on release.
/// A plain button style leaves the row inert until the action completes, which
/// reads as a dead click.
struct NotchRowButtonStyle: ButtonStyle {
    var isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && isEnabled ? 0.985 : 1)
            .brightness(configuration.isPressed && isEnabled ? 0.06 : 0)
            .animation(NotchDesign.pressSpring, value: configuration.isPressed)
    }
}
