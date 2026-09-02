import AppKit
import SwiftUI

struct NotchPanelView: View {
    let store: SessionStore
    let pendingStore: PendingStore
    let focusDispatcher: FocusDispatcher
    let decisionWriter: ApprovalDecisionWriter
    let onApprovalDismiss: @MainActor (String) -> Void
    let onSizeChange: @MainActor (CGSize) -> Void
    let reveal: HUDRevealState
    /// Width of the collapsed notch band — where the reveal starts from.
    let compactWidth: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var feedback: [String: SessionRowFeedback] = [:]
    @State private var sessionListHeight: CGFloat?

    private let maximumPanelHeight: CGFloat = 520
    /// Only true when rows actually run under the chrome. Fading the edges of a
    /// short, fully visible list would dim the first and last row for nothing.
    private var listIsScrollable: Bool {
        (sessionListHeight ?? 0) > maximumSessionListHeight
    }

    private var maximumSessionListHeight: CGFloat {
        pendingStore.hasPending ? 205 : 468
    }

    private let panelShape = UnevenRoundedRectangle(
        cornerRadii: RectangleCornerRadii(
            topLeading: 0,
            bottomLeading: 22,
            bottomTrailing: 22,
            topTrailing: 0
        ),
        style: .continuous
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if let approval = pendingStore.current {
                ApprovalCardView(
                    approval: approval,
                    decisionWriter: decisionWriter,
                    onDismiss: onApprovalDismiss
                )
            }

            TimelineView(.periodic(from: .now, by: 30)) { context in
                if store.sessions.isEmpty {
                    emptyState
                } else {
                    ScrollView(.vertical) {
                        VStack(spacing: 6) {
                            ForEach(store.sessions) { session in
                                SessionRowView(
                                    session: session,
                                    now: context.date,
                                    feedback: feedback[session.id],
                                    onSelect: focus,
                                    onGrantAccess: openAutomationSettings
                                )
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .background {
                            GeometryReader { proxy in
                                Color.clear
                                    .onAppear {
                                        sessionListHeight = proxy.size.height
                                    }
                                    .onChange(of: proxy.size.height) { _, height in
                                        sessionListHeight = height
                                    }
                            }
                        }
                    }
                    .frame(
                        height: min(
                            sessionListHeight ?? maximumSessionListHeight,
                            maximumSessionListHeight
                        )
                    )
                    // Scroll edge effect rather than a hard divider: content
                    // dissolves where it meets the chrome instead of being
                    // sliced by a line. Drawn as a non-interactive overlay, not
                    // a mask, so it cannot swallow clicks on the edge rows.
                    .overlay(alignment: .top) {
                        if listIsScrollable {
                            LinearGradient(
                                colors: [NotchDesign.surface, .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 12)
                            .allowsHitTesting(false)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if listIsScrollable {
                            LinearGradient(
                                colors: [.clear, NotchDesign.surface],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 12)
                            .allowsHitTesting(false)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 14)
        .frame(
            minWidth: NotchPanelMetrics.width,
            maxWidth: NotchPanelMetrics.width,
            maxHeight: maximumPanelHeight,
            alignment: .top
        )
        .fixedSize(horizontal: false, vertical: true)
        // Pure opaque black to match the notch band above, which DynamicNotchKit
        // fills with plain `.black`. Any tint or translucency here shows up as a
        // step across the seam.
        .background(NotchDesign.surface)
        .clipShape(panelShape)
        .mask {
            // Width-only reveal, matched to the band's animation. The inner frame
            // is what animates; the outer keeps the layout size fixed at full
            // width so nothing below it shifts.
            //
            // Reduced motion replaces the travel with a plain cross-fade: the
            // information still arrives, it just does not sweep across the screen.
            Color.black
                .frame(
                    width: reduceMotion
                        ? NotchPanelMetrics.width
                        : (reveal.isRevealed ? NotchPanelMetrics.width : compactWidth)
                )
                .frame(width: NotchPanelMetrics.width)
                .animation(
                    reveal.isRevealed
                        ? NotchPanelMetrics.openAnimation
                        : NotchPanelMetrics.closeAnimation,
                    value: reveal.isRevealed
                )
        }
        .opacity(reduceMotion ? (reveal.isRevealed ? 1 : 0) : 1)
        .animation(reduceMotion ? NotchDesign.reducedMotion : nil, value: reveal.isRevealed)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        onSizeChange(proxy.size)
                    }
                    .onChange(of: proxy.size) { _, size in
                        onSizeChange(size)
                    }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            HStack(spacing: 4) {
                summaryPart(store.counts.working, "working", color: DisplayStatus.working.color)
                summarySeparator
                summaryPart(store.counts.needsMe, "needs you", color: DisplayStatus.needsMe.color)
                summarySeparator
                summaryPart(store.counts.done, "done", color: DisplayStatus.done.color)
            }

            Spacer()

            Image(systemName: "gearshape")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NotchDesign.textTertiary)
                .accessibilityLabel("Settings")
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .tracking(NotchDesign.tracking(forSize: 11))
    }

    private func summaryPart(_ count: Int, _ label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Text("\(count)")
                .foregroundStyle(color)
                .monospacedDigit()
            Text(label)
                .foregroundStyle(NotchDesign.textSecondary)
        }
    }

    private var summarySeparator: some View {
        Text("·")
            .foregroundStyle(NotchDesign.textQuaternary)
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            AgentSprite(status: .idle, size: 18)
            Text("No active sessions")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .tracking(NotchDesign.tracking(forSize: 12))
                .foregroundStyle(NotchDesign.textTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .center)
    }

    private func focus(_ session: Session) {
        HoverDiag.log(
            "focus tapped id=\(session.id) focusable=\(session.isFocusable) "
                + "tty=\(session.terminal?.tty ?? "nil") "
                + "app=\(session.terminal?.appBundleId ?? "nil") "
                + "entrypoint=\(session.terminal?.claudeEntrypoint ?? "nil")"
        )
        guard session.isFocusable else {
            HoverDiag.log("focus refused: session is not focusable")
            return
        }
        feedback[session.id] = nil

        Task {
            let result = await focusDispatcher.focus(session)
            HoverDiag.log("focus result id=\(session.id) -> \(result)")
            switch result {
            case .success:
                break
            case .failure(.permissionDenied):
                show(.permissionDenied, for: session.id, duration: .seconds(10))
            case .failure(.notFound), .failure(.scriptFailed):
                show(.notFound, for: session.id, duration: .seconds(2))
            }
        }
    }

    private func show(_ value: SessionRowFeedback, for sessionID: String, duration: Duration) {
        feedback[sessionID] = value

        Task {
            try? await Task.sleep(for: duration)
            if feedback[sessionID] == value {
                feedback[sessionID] = nil
            }
        }
    }

    private func openAutomationSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        ) else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}
