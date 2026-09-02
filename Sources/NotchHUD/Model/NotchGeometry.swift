import CoreGraphics

enum NotchGeometry {
    /// The physical notch cutout rect from a screen's auxiliary areas.
    /// Returns nil when there is no notch (no valid aux gap).
    static func notchRect(
        auxLeftMaxX: CGFloat?,
        auxRightMinX: CGFloat?,
        frameMaxY: CGFloat,
        safeTop: CGFloat
    ) -> CGRect? {
        guard
            let auxLeftMaxX,
            let auxRightMinX,
            auxRightMinX > auxLeftMaxX
        else {
            return nil
        }

        return CGRect(
            x: auxLeftMaxX,
            y: frameMaxY - safeTop,
            width: auxRightMinX - auxLeftMaxX,
            height: safeTop
        )
    }

    /// Widened trigger zone covering the visible peek beside the cutout.
    ///
    /// `topExtra` pushes the top edge ABOVE the screen, which is not cosmetic:
    /// `CGRect.contains` is half-open on the max edges, and the pointer pinned to
    /// the very top of the display reports exactly `frameMaxY`. Without the
    /// overshoot the topmost row of the notch — where the pointer naturally lands
    /// when you shove it upward — tests as outside the rect and never triggers.
    static func hitRect(
        from notchRect: CGRect,
        sideMargin: CGFloat,
        bottomExtra: CGFloat,
        topExtra: CGFloat = 4
    ) -> CGRect {
        CGRect(
            x: notchRect.minX - sideMargin,
            y: notchRect.minY - bottomExtra,
            width: notchRect.width + (sideMargin * 2),
            height: notchRect.height + bottomExtra + topExtra
        )
    }

    /// Fallback centered rect when there is no notch.
    static func fallbackRect(
        frameMidX: CGFloat,
        frameMaxY: CGFloat,
        visibleMaxY: CGFloat,
        width: CGFloat
    ) -> CGRect {
        let height = max(frameMaxY - visibleMaxY, 32)
        return CGRect(
            x: frameMidX - (width / 2),
            y: frameMaxY - height,
            width: width,
            height: height
        )
    }

    /// Expanded-content hit region (for keeping the panel open while the pointer is over it).
    static func expandedContentRect(
        frameMidX: CGFloat,
        frameMaxY: CGFloat,
        notchHeight: CGFloat,
        width: CGFloat,
        height: CGFloat
    ) -> CGRect {
        let totalHeight = height + notchHeight
        return CGRect(
            x: frameMidX - (width / 2),
            y: frameMaxY - totalHeight,
            width: width,
            height: totalHeight
        )
    }
}
