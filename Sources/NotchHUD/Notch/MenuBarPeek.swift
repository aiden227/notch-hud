import AppKit
import SwiftUI

/// Stand-in for the notch on displays that have none. Sits inside the menu bar
/// strip at top center -- the same dead space a notch occupies -- so it never
/// covers window content, ignores clicks, and draws nothing while idle.
@MainActor
final class MenuBarPeek {
    static let width: CGFloat = 300

    private let panel: NSPanel

    init(store: SessionStore, pendingStore: PendingStore) {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.animationBehavior = .none
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(
            rootView: MenuBarPeekView(store: store, pendingStore: pendingStore)
        )
    }

    func show(on screen: NSScreen) {
        let height = max(screen.frame.maxY - screen.visibleFrame.maxY, 24)
        panel.setFrame(
            NSRect(
                x: screen.frame.midX - Self.width / 2,
                y: screen.frame.maxY - height,
                width: Self.width,
                height: height
            ),
            display: true
        )
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func close() {
        panel.orderOut(nil)
        panel.close()
    }
}

private struct MenuBarPeekView: View {
    let store: SessionStore
    let pendingStore: PendingStore

    var body: some View {
        ZStack {
            if store.total > 0 || pendingStore.hasPending {
                HStack(spacing: 12) {
                    NotchPeekView(store: store, pendingStore: pendingStore)
                    NotchPeekTrailingView(store: store)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(MenuBarMaterial().clipShape(Capsule()))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
