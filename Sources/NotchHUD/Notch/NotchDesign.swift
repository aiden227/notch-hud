import AppKit
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

    static let textPrimary = Color.primary

    /// Text at `opacity` on the black notch. The grey menu-bar surface has far
    /// less contrast, so the same step reads too faint there; lift it.
    static func text(_ opacity: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor.white.withAlphaComponent(opacity)
                : NSColor.black.withAlphaComponent(min(1, 0.3 + 0.8 * opacity))
        })
    }
    static let textSecondary = text(0.72)
    static let textTertiary = text(0.58)
    static let textQuaternary = text(0.44)

    /// Increased-contrast variants, used when the system asks for more contrast.
    static let textSecondaryHC = text(0.90)
    static let textTertiaryHC = text(0.80)
    static let textQuaternaryHC = text(0.70)

    // MARK: - Surfaces

    /// Opaque black, matching the notch band above.
    ///
    /// Deliberately NOT a translucent material: the physical notch is a real
    /// black cutout, and the expanded surface has to read as the same object
    /// growing out of it. Translucency would separate them into two things.
    static let surface = Color.black

    /// Text on a primary-filled button: black in dark mode, white in light.
    static let inverse = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .black : .white
    })
    /// Inset wells (code, paths). Darken on dark, barely tint on light.
    static let well = adaptive(dark: 0.22, light: 0.06)
    static let wellDeep = adaptive(dark: 0.28, light: 0.08)

    private static func adaptive(dark: CGFloat, light: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            NSColor.black.withAlphaComponent(
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            )
        })
    }

    /// Resting row fill. Only on the black notch surface; on the menu-bar
    /// surface rows sit flat, with a fill only on hover.
    static let rowFill = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor.white.withAlphaComponent(0.05)
            : .clear
    })
    static let rowFillHover = Color.primary.opacity(0.10)
    static let rowFillPressed = Color.primary.opacity(0.16)
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

/// The menu bar's own color, for growing out of it on a display with no notch.
/// Solid, not a blur: the menu bar here is opaque (#DADADA measured in light
/// mode), and a behind-window blur picks up whatever window sits under the
/// panel instead -- white over a browser page.
struct MenuBarMaterial: View {
    var body: some View { Self.color }

    static let color = Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 0.16, alpha: 1)
                : NSColor(white: 218.0 / 255.0, alpha: 1)
    })
}
