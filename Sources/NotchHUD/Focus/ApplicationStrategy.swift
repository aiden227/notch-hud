import AppKit

/// Last-resort focus for sessions with no controlling tty — Claude Code running
/// inside an editor rather than a terminal.
///
/// There is no terminal window to raise and nothing identifies the individual
/// editor tab, so this raises the owning application and stops there. It runs
/// only when every tty-based strategy has declined, and unlike those it drives
/// AppKit directly rather than AppleScript, so it needs no Automation grant.
struct ApplicationStrategy: FocusStrategy {
    func canHandle(_ identity: TerminalIdentity) -> Bool {
        identity.tty == nil && identity.appBundleId != nil
    }

    func focus(_ identity: TerminalIdentity) throws {
        guard let bundleID = identity.appBundleId else {
            throw FocusError.notFound
        }

        // Deliberately does NOT launch the app if it is not running: the session
        // belongs to a live process, so a missing app means the record is stale.
        let running = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleID
        )
        guard let application = running.first else {
            throw FocusError.notFound
        }

        guard application.activate(options: [.activateAllWindows]) else {
            throw FocusError.notFound
        }
    }
}
