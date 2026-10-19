import AppKit
import DynamicNotchKit
import SwiftUI

@MainActor
final class NotchWindowManager {
    enum ExpansionReason: String {
        case hover
        case pending
        case attention
        case manual
    }

    private typealias NotchedHUD = DynamicNotch<NotchExpandedSpacer, NotchPeekView, NotchPeekTrailingView>

    // Band and panel must change state at the same rate or the HUD visibly comes
    // apart. Opening unfurls over 0.2s; closing is instant.
    // See NotchPanelMetrics.

    private let environment: AppEnvironment
    private let store: SessionStore
    private let pendingStore: PendingStore
    private let focusDispatcher: FocusDispatcher
    private let decisionWriter: ApprovalDecisionWriter
    private var hoverController: HoverController?
    private var selectedScreen: NSScreen?
    private var notchedHUD: NotchedHUD?
    private var menuBarPeek: MenuBarPeek?
    private var interactivePanel: InteractiveNotchPanel?
    private let reveal = HUDRevealState()
    /// Highest `seq` per session the user has actually looked at. A session
    /// needing attention re-alerts only when the agent emits something newer,
    /// so acknowledging is not undone by unrelated rescans.
    private var acknowledgedSeq: [String: Int] = [:]
    private var attentionAutoExpandActive = false
    /// Whether the pointer is anywhere over the HUD — the band OR the panel.
    /// `containsExpandedContent` only covers the panel, and the band alone is a
    /// perfectly good place to be reading from.
    private var pointerIsOverHUD = false
    private var activationObserver: (any NSObjectProtocol)?
    private var hideTask: Task<Void, Never>?
    private var panelHostingView: NSHostingView<NotchPanelView>?
    private var transitionTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    private var globalMouseDownMonitor: Any?
    private var localEventMonitor: Any?
    private var transitionGeneration = 0
    private var renderedPanelSize: CGSize?
    private var pendingAutoExpandActive = false
    private(set) var isExpanded = false
    private(set) var expansionReason: ExpansionReason?

    init(
        environment: AppEnvironment,
        store: SessionStore,
        pendingStore: PendingStore,
        focusDispatcher: FocusDispatcher
    ) {
        self.environment = environment
        self.store = store
        self.pendingStore = pendingStore
        self.focusDispatcher = focusDispatcher
        decisionWriter = ApprovalDecisionWriter(
            decisionsURL: environment.decisionsURL,
            sessionAllowURL: environment.sessionAllowURL
        )
    }

    func boot() {
        _ = environment.spoolURL
        _ = environment.pendingURL

        let hoverController = HoverController(delegate: self)
        self.hoverController = hoverController
        installInteractionMonitors()
        installActivationObserver()
        repinToBuiltInScreen()
    }

    func shutdown() {
        hoverController?.suspend()
        transitionTask?.cancel()
        watchdogTask?.cancel()
        removeInteractionMonitors()
        removeActivationObserver()
        removeInteractivePanel()
    }

    func repinToBuiltInScreen() {
        guard let screen = preferredScreen() else {
            NSLog("NotchHUD could not find a screen to pin to.")
            return
        }

        hoverController?.suspend()
        selectedScreen = screen
        resetExpansionState(reason: .manual)
        renderedPanelSize = nil

        transitionGeneration += 1
        let generation = transitionGeneration
        transitionTask?.cancel()
        transitionTask = Task { [weak self] in
            guard let self else { return }
            await self.hideEveryNotch()
            guard self.transitionGeneration == generation else { return }

            self.clearNotches()
            if screen.safeAreaInsets.top > 0 {
                NSLog(
                    "NotchHUD pinning the notched HUD to %@ (%d screen(s)).",
                    screen.localizedName, NSScreen.screens.count
                )
                await self.installNotchedHUD(on: screen, generation: generation)
            } else {
                NSLog("NotchHUD found no notched display; using a menu-bar peek.")
                await self.installFloatingHUD(on: screen, generation: generation)
            }

            guard self.transitionGeneration == generation, !self.isExpanded else { return }
            self.installInteractivePanel()
            self.hoverController?.pin(to: screen)
            if self.pendingStore.hasPending {
                self.pendingAutoExpandActive = true
                self.expand(reason: .pending)
            } else {
                self.pendingAutoExpandActive = false
            }
            // Catch up on anything that already needed attention while the HUD
            // was still being built.
            self.sessionsDidChange()

            // A close sent while the display is asleep or mid-reconfigure can be
            // dropped by the window server, leaving an empty peek on screen as a
            // black bar. Sweep now, and again once the wake has fully settled.
            self.sweepOrphanedWindows()
            try? await Task.sleep(for: .seconds(3))
            guard self.transitionGeneration == generation else { return }
            self.sweepOrphanedWindows()
        }
    }

    func applyPendingApprovals(_ approvals: [PendingApproval]) {
        let previouslyHadPending = pendingStore.hasPending
        pendingStore.apply(approvals)
        store.markPendingApprovals(sessionIDs: Set(approvals.map(\.sessionId)))
        handlePendingTransition(previouslyHadPending: previouslyHadPending)
    }

    /// The user jumped to an agent from its row.
    func sessionDidReceiveFocus(id: String) {
        clearFinishedSession(id: id)
    }

    private func approvalDidResolve(sessionID: String) {
        let previouslyHadPending = pendingStore.hasPending
        pendingStore.dismiss(sessionID: sessionID)
        store.markPendingApprovals(sessionIDs: Set(pendingStore.approvals.map(\.sessionId)))
        handlePendingTransition(previouslyHadPending: previouslyHadPending)
    }

    private func handlePendingTransition(previouslyHadPending: Bool) {
        if pendingStore.hasPending {
            pendingAutoExpandActive = true
            expand(reason: .pending)
            return
        }

        guard previouslyHadPending || pendingAutoExpandActive else { return }
        pendingAutoExpandActive = false
        if !containsExpandedContent(at: NSEvent.mouseLocation) {
            collapse(reason: .pending)
        }
    }

    /// Sessions that have finished or are blocked on the user and have not been
    /// viewed since. These hold the HUD open.
    private var unacknowledgedAttention: [Session] {
        store.sessions.filter { session in
            guard session.displayStatus == .needsMe || session.displayStatus == .done else {
                return false
            }
            return session.seq > (acknowledgedSeq[session.id] ?? Int.min)
        }
    }

    private var hasUnacknowledgedAttention: Bool {
        !unacknowledgedAttention.isEmpty
    }

    /// Called when the spool changes: open the HUD for anything newly needing
    /// attention, and let it close again once everything has been seen.
    func sessionsDidChange() {
        // Drop bookkeeping for sessions that have left the spool entirely.
        let liveIDs = Set(store.sessions.map(\.id))
        acknowledgedSeq = acknowledgedSeq.filter { liveIDs.contains($0.key) }

        if hasUnacknowledgedAttention {
            // Already looking at the HUD when it arrived — that counts as seen,
            // otherwise the HUD would stick open until the pointer left and
            // came back.
            if isExpanded,
               pointerIsOverHUD || containsExpandedContent(at: NSEvent.mouseLocation) {
                acknowledgeAttention()
                return
            }
            attentionAutoExpandActive = true
            expand(reason: .attention)
            return
        }

        guard attentionAutoExpandActive else { return }
        attentionAutoExpandActive = false
        if !containsExpandedContent(at: NSEvent.mouseLocation) {
            collapse(reason: .attention)
        }
    }

    /// The user has looked at the HUD, so everything currently showing counts as
    /// seen and no longer holds the panel open.
    private func acknowledgeAttention() {
        for session in unacknowledgedAttention {
            acknowledgedSeq[session.id] = session.seq
        }
        attentionAutoExpandActive = false
    }

    func expand(reason: ExpansionReason) {
        HoverDiag.log(
            "expand(reason: \(reason.rawValue)) isExpanded=\(isExpanded) "
                + "selectedScreen=\(selectedScreen != nil) notchedHUD=\(notchedHUD != nil)"
        )
        guard !isExpanded, let screen = selectedScreen else { return }
        guard notchedHUD != nil || menuBarPeek != nil else { return }
        // The panel is installed after the notch during boot. Expanding in that
        // window would set isExpanded with nothing to show, and the installer's
        // own `!isExpanded` guard would then skip installing the panel and
        // pinning hover for good. Boot re-checks attention once both exist.
        guard interactivePanel != nil else {
            HoverDiag.log("expand(reason: \(reason.rawValue)) deferred: panel not installed yet")
            return
        }

        isExpanded = true
        expansionReason = reason
        startWatchdog()

        transitionGeneration += 1
        let generation = transitionGeneration
        transitionTask?.cancel()
        showInteractivePanel()

        if let notchedHUD {
            configurePassThroughWindow(notchedHUD.windowController?.window)
            transitionTask = Task { [weak self, weak notchedHUD] in
                guard let self, let notchedHUD else { return }
                notchedHUD.transitionConfiguration.conversionAnimation =
                    NotchPanelMetrics.openAnimation
                await notchedHUD.expand(on: screen)
                guard self.transitionGeneration == generation, self.isExpanded else { return }
                self.configurePassThroughWindow(notchedHUD.windowController?.window)
                self.showInteractivePanel()
            }
            return
        }

        menuBarPeek?.hide()
    }

    func collapse(reason: ExpansionReason) {
        if reason == .hover, pendingAutoExpandActive, pendingStore.hasPending {
            HoverDiag.log("collapse(reason: hover) ignored while a pending card is showing")
            return
        }
        if reason == .hover, hasUnacknowledgedAttention {
            HoverDiag.log(
                "collapse(reason: hover) ignored: "
                    + "\(unacknowledgedAttention.count) session(s) not yet viewed"
            )
            return
        }
        guard isExpanded else { return }

        HoverDiag.log("collapse(reason: \(reason.rawValue))")
        isExpanded = false
        expansionReason = nil
        watchdogTask?.cancel()
        watchdogTask = nil
        reveal.isRevealed = false
        hideTask?.cancel()
        // Let the closing spring actually render before the window goes away, so
        // panel and band travel together. Re-expanding cancels this.
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(NotchPanelMetrics.closeSettle))
            guard let self, !self.isExpanded else { return }
            self.interactivePanel?.orderOut(nil)
        }

        transitionGeneration += 1
        let generation = transitionGeneration
        transitionTask?.cancel()
        guard let screen = selectedScreen else { return }

        if let notchedHUD {
            configurePassThroughWindow(notchedHUD.windowController?.window)
            transitionTask = Task { [weak self, weak notchedHUD] in
                guard let self, let notchedHUD else { return }
                notchedHUD.transitionConfiguration.conversionAnimation =
                    NotchPanelMetrics.closeAnimation
                await notchedHUD.compact(on: screen)
                guard self.transitionGeneration == generation, !self.isExpanded else { return }
                self.configurePassThroughWindow(notchedHUD.windowController?.window)
            }
            return
        }

        menuBarPeek?.show(on: screen)
    }

    func containsExpandedContent(at point: NSPoint) -> Bool {
        guard isExpanded, let panel = interactivePanel, panel.isVisible else { return false }
        return panel.frame.contains(point)
    }

    /// An external display wins over the built-in notch: when the MacBook is
    /// plugged into a monitor, the HUD follows to that monitor as the menu-bar
    /// pill. The primary (menu-bar) display is preferred if it is external.
    /// With no external attached, fall back to the notched built-in screen.
    private func preferredScreen() -> NSScreen? {
        let screens = NSScreen.screens
        if let primary = screens.first, !primary.isBuiltIn { return primary }
        if let external = screens.first(where: { !$0.isBuiltIn }) { return external }
        return screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? screens.first
    }

    private func installNotchedHUD(on screen: NSScreen, generation: Int) async {
        let store = store
        let pendingStore = pendingStore
        let notch = NotchedHUD(
            hoverBehavior: [],
            style: .notch(
                topCornerRadius: NotchPanelMetrics.expandedTopCornerRadius,
                bottomCornerRadius: NotchPanelMetrics.expandedBottomCornerRadius
            ),
            // Transparent spacer, not empty: it gives the expanded notch band the
            // panel's width so the two windows fuse into one surface. Zero height
            // keeps the band exactly the height of the physical notch.
            expanded: { NotchExpandedSpacer() },
            compactLeading: { NotchPeekView(store: store, pendingStore: pendingStore) },
            compactTrailing: { NotchPeekTrailingView(store: store) }
        )
        notch.transitionConfiguration.skipIntermediateHides = true
        notchedHUD = notch

        await notch.compact(on: screen)
        guard transitionGeneration == generation else {
            // A newer repin started while this one was animating in.
            notch.windowController?.close()
            notch.windowController = nil
            return
        }
        guard !isExpanded else { return }
        configurePassThroughWindow(notch.windowController?.window)
    }

    private func installFloatingHUD(on screen: NSScreen, generation: Int) async {
        let peek = MenuBarPeek(store: store, pendingStore: pendingStore)
        menuBarPeek = peek
        guard transitionGeneration == generation, !isExpanded else { return }
        peek.show(on: screen)
    }

    private func installInteractivePanel() {
        removeInteractivePanel()

        let store = store
        let pendingStore = pendingStore
        let focusDispatcher = focusDispatcher
        let decisionWriter = decisionWriter
        let compactWidth = selectedScreen.map {
            NotchGeometry.notchRect(
                auxLeftMaxX: $0.auxiliaryTopLeftArea?.maxX,
                auxRightMinX: $0.auxiliaryTopRightArea?.minX,
                frameMaxY: $0.frame.maxY,
                safeTop: $0.safeAreaInsets.top
            )?.width
        } ?? nil
        let rootView = NotchPanelView(
            store: store,
            pendingStore: pendingStore,
            focusDispatcher: focusDispatcher,
            decisionWriter: decisionWriter,
            onApprovalDismiss: { [weak self] sessionID in
                self?.approvalDidResolve(sessionID: sessionID)
            },
            onSessionFocused: { [weak self] sessionID in
                self?.sessionDidReceiveFocus(id: sessionID)
            },
            onSizeChange: { [weak self] size in
                self?.updateRenderedPanelSize(size)
            },
            reveal: reveal,
            compactWidth: compactWidth ?? 220,
            isNotchless: menuBarPeek != nil
        )
        let hostingView = FirstMouseHostingView(rootView: rootView)
        // The notch is black whatever the system theme; the menu bar is not.
        hostingView.appearance = menuBarPeek == nil ? NSAppearance(named: .darkAqua) : nil
        hostingView.autoresizingMask = [.width, .height]

        let panel = InteractiveNotchPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // No shadow: the notch band above casts none, so a shadow on the panel
        // alone draws a rim along the seam and gives away that this is two
        // windows rather than one surface.
        panel.hasShadow = false
        // AppKit fades panels in and out on its own. Mid-fade the panel is
        // see-through, and the window edge under the menu bar blinks through it.
        panel.animationBehavior = .none
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.ignoresMouseEvents = false
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary
        ]
        panel.onEscape = { [weak self] in
            self?.collapse(reason: .manual)
        }

        interactivePanel = panel
        panelHostingView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        let fittingSize = hostingView.fittingSize
        if fittingSize.width > 0, fittingSize.height > 0 {
            updateRenderedPanelSize(fittingSize)
        }
    }

    private func showInteractivePanel() {
        guard isExpanded, let panel = interactivePanel else { return }

        if renderedPanelSize == nil, let hostingView = panelHostingView {
            hostingView.layoutSubtreeIfNeeded()
            let fittingSize = hostingView.fittingSize
            if fittingSize.width > 0, fittingSize.height > 0 {
                updateRenderedPanelSize(fittingSize)
            }
        }

        guard renderedPanelSize != nil else {
            // Never make an unmeasured (and potentially oversized) panel interactive.
            return
        }
        positionInteractivePanel()
        hideTask?.cancel()
        hideTask = nil
        // Show without taking key status: an auto-expand (agent finished, approval
        // pending) must never pull keystrokes away from the app being typed in.
        // The panel becomes key only when the user actually clicks it.
        panel.orderFrontRegardless()
        // Next runloop turn: the mask must render at compactWidth once before the
        // change to full width can animate rather than snap.
        Task { @MainActor [weak self] in
            guard let self, self.isExpanded else { return }
            self.reveal.isRevealed = true
        }
    }

    private func updateRenderedPanelSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        renderedPanelSize = CGSize(
            width: ceil(min(size.width, 720)),
            height: ceil(min(size.height, 560))
        )
        positionInteractivePanel()
        if isExpanded, interactivePanel?.isVisible != true {
            showInteractivePanel()
        }
    }

    private func positionInteractivePanel() {
        guard
            let panel = interactivePanel,
            let screen = selectedScreen,
            let panelSize = renderedPanelSize
        else {
            return
        }

        // Must match the band DynamicNotchKit actually draws, which is
        // `NSScreen.notchSize.height` -- i.e. safeAreaInsets.top on a notched
        // display. Using max(safeTop, menubarHeight) here left the panel 2pt low
        // on this hardware (safeTop 38, menubar 40), opening a gap that showed
        // the desktop between the band and the panel.
        let notchBandHeight = screen.safeAreaInsets.top > 0
            ? screen.safeAreaInsets.top
            : screen.frame.maxY - screen.visibleFrame.maxY
        let frame = NSRect(
            x: screen.frame.midX - (panelSize.width / 2),
            y: screen.frame.maxY - notchBandHeight - panelSize.height
                + NotchPanelMetrics.seamOverlap,
            width: panelSize.width,
            height: panelSize.height
        )
        panel.setFrame(frame, display: panel.isVisible)
    }

    private func removeInteractivePanel() {
        // Reset so a rebuilt panel (screen change, re-pin) unfurls again rather
        // than appearing already at full width.
        hideTask?.cancel()
        hideTask = nil
        reveal.isRevealed = false
        interactivePanel?.onEscape = nil
        interactivePanel?.orderOut(nil)
        interactivePanel?.close()
        interactivePanel = nil
        panelHostingView = nil
    }

    private func configurePassThroughWindow(_ window: NSWindow?) {
        guard let window else { return }
        window.ignoresMouseEvents = true
        // Only the notch band uses this; it is black whatever the system theme.
        window.appearance = NSAppearance(named: .darkAqua)
        window.level = .statusBar
        window.collectionBehavior.formUnion([
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary
        ])
    }

    private func installInteractionMonitors() {
        guard globalMouseDownMonitor == nil, localEventMonitor == nil else { return }

        globalMouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) {
            [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleLeftMouseDown(at: NSEvent.mouseLocation)
            }
        }

        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .keyDown]
        ) { [weak self] event in
            guard let self else { return event }

            if event.type == .keyDown, event.keyCode == 53, self.isExpanded {
                self.collapse(reason: .manual)
                return nil
            }
            if event.type == .leftMouseDown {
                self.handleLeftMouseDown(at: NSEvent.mouseLocation)
            }
            return event
        }
    }

    /// Bringing an agent's host app to the front IS reading its results, so the
    /// finished rows for that app have done their job and are cleared.
    /// `needs_me` is deliberately left alone: activating the app does not answer
    /// the question the agent is blocked on.
    private func installActivationObserver() {
        guard activationObserver == nil else { return }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication,
                let bundleID = application.bundleIdentifier
            else {
                return
            }
            MainActor.assumeIsolated {
                self?.clearFinishedSessions(hostedBy: bundleID)
            }
        }
    }

    private func removeActivationObserver() {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
    }

    private func clearFinishedSessions(hostedBy bundleID: String) {
        clearFinished(reason: "activation of \(bundleID)") {
            $0.terminal?.appBundleId == bundleID
        }
    }

    /// Everything finished, regardless of host — used once the user has looked at
    /// the HUD and moved on. Waiting for an app switch to tidy up is exactly the
    /// case that leaves finished rows sitting there while the user is already
    /// working in the app that produced them.
    private func clearFinishedSessions() {
        clearFinished(reason: "viewed") { _ in true }
    }

    /// One finished session, cleared because the user jumped to it. Opening the
    /// agent is the most direct possible acknowledgement that it has been read.
    private func clearFinishedSession(id: String) {
        clearFinished(reason: "jumped to \(id)") { $0.id == id }
    }

    private func clearFinished(
        reason: String,
        matching predicate: (Session) -> Bool
    ) {
        let sessions = store.sessionsWithoutPendingOverlay
        let finishedIDs = Set(
            sessions
                .filter { $0.displayStatus == .done && predicate($0) }
                .map(\.id)
        )
        guard !finishedIDs.isEmpty else { return }

        HoverDiag.log("\(reason) cleared \(finishedIDs.count) finished session(s)")
        for id in finishedIDs {
            SpoolFile.remove(sessionID: id, in: environment.spoolURL)
            acknowledgedSeq[id] = nil
        }
        store.apply(sessions.filter { !finishedIDs.contains($0.id) })
    }

    private func removeInteractionMonitors() {
        if let globalMouseDownMonitor {
            NSEvent.removeMonitor(globalMouseDownMonitor)
            self.globalMouseDownMonitor = nil
        }
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
    }

    private func handleLeftMouseDown(at point: NSPoint) {
        guard isExpanded, !containsExpandedContent(at: point) else { return }
        collapse(reason: .manual)
    }

    private func startWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = Task { @MainActor [weak self] in
            var lastPointerInsideTime = ProcessInfo.processInfo.systemUptime

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(5))
                } catch {
                    return
                }
                guard let self, self.isExpanded else { return }

                let now = ProcessInfo.processInfo.systemUptime
                if self.containsExpandedContent(at: NSEvent.mouseLocation) {
                    lastPointerInsideTime = now
                } else if self.hasUnacknowledgedAttention {
                    // Held open on purpose until viewed; not a stuck panel.
                    lastPointerInsideTime = now
                } else if now - lastPointerInsideTime >= 120 {
                    NSLog(
                        "NotchHUD watchdog force-collapsed a panel left expanded "
                            + "for 120 seconds without the pointer inside."
                    )
                    self.collapse(reason: .manual)
                    return
                }
            }
        }
    }

    private func resetExpansionState(reason: ExpansionReason) {
        if isExpanded {
            HoverDiag.log("resetExpansionState(reason: \(reason.rawValue))")
        }
        isExpanded = false
        expansionReason = nil
        watchdogTask?.cancel()
        watchdogTask = nil
        interactivePanel?.orderOut(nil)
    }

    private func hideEveryNotch() async {
        if let notchedHUD {
            await notchedHUD.hide()
        }
        menuBarPeek?.hide()
    }

    /// Closes any HUD panel this app still has on screen that isn't the
    /// current peek, notch or interactive panel.
    private func sweepOrphanedWindows() {
        let keep: [NSWindow?] = [
            menuBarPeek?.panel,
            interactivePanel,
            notchedHUD?.windowController?.window,
        ]
        for window in NSApp.windows {
            let isPeek = window.identifier == MenuBarPeek.windowIdentifier
            let isPanel = window is InteractiveNotchPanel
            // DynamicNotchKit's panel class is internal to the package, so match by name.
            let isNotch = String(describing: type(of: window)) == "DynamicNotchPanel"
            guard isPeek || isPanel || isNotch else { continue }
            guard !keep.contains(where: { $0 === window }) else { continue }
            NSLog(
                "NotchHUD closing an orphaned HUD window (%@).",
                isPeek ? "peek" : (isPanel ? "panel" : "notch")
            )
            window.orderOut(nil)
            window.close()
        }
    }

    private func clearNotches() {
        removeInteractivePanel()
        // Close the window outright. Dropping the reference alone can orphan a
        // notch whose compact animation finished after hide() ran (a display
        // wake fires several screen changes in a row), leaving a black notch
        // that nothing owns.
        notchedHUD?.windowController?.close()
        notchedHUD?.windowController = nil
        notchedHUD = nil
        menuBarPeek?.close()
        menuBarPeek = nil
    }
}

extension NotchWindowManager: HoverControllerDelegate {
    func hoverControllerDidEnter(_ controller: HoverController) {
        pointerIsOverHUD = true
        acknowledgeAttention()
        expand(reason: .hover)
    }

    func hoverControllerDidExit(_ controller: HoverController) {
        pointerIsOverHUD = false
        collapse(reason: .hover)
        // Deliberately on exit rather than enter: clearing as the pointer
        // arrives would delete the rows the user came to read, out from under
        // the cursor, before they could be clicked.
        clearFinishedSessions()
    }

    func hoverController(_ controller: HoverController, containsExpandedPoint point: NSPoint) -> Bool {
        containsExpandedContent(at: point)
    }
}

@MainActor
/// Hosting view that acts on the first click even when its panel is not key —
/// a floating approval card must respond immediately, never swallow a click to "focus".
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class InteractiveNotchPanel: NSPanel {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}

private extension NSScreen {
    var isBuiltIn: Bool {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return false
        }
        return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) != 0
    }
}
