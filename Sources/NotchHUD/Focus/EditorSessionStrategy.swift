import AppKit

/// Jumps to the exact tab of a Claude Code session hosted inside a VS Code-family
/// editor (VS Code, Cursor, Antigravity IDE, …).
///
/// The Claude Code extension registers a URI handler:
///
///     case "/open": {
///         let session = query.get("session"), prompt = query.get("prompt")
///         commands.executeCommand("claude-vscode.primaryEditor.open", session, prompt)
///     }
///
/// so `<scheme>://Anthropic.claude-code/open?session=<uuid>` reveals that
/// conversation. Opening a URL needs no Accessibility or Screen Recording grant,
/// which is why this is preferred over walking the window list: an editor window
/// hosts every session in one process and nothing in the accessibility tree
/// distinguishes the tabs.
struct EditorSessionStrategy: FocusStrategy {
    /// Authority of the URI — the Claude Code extension's `publisher.name`.
    private static let extensionIdentifier = "Anthropic.claude-code"

    /// The spool id is the agent session id with this prefix; the URI wants it bare.
    private static let sessionIDPrefix = "claude-"

    func canHandle(_ identity: TerminalIdentity) -> Bool {
        identity.tty == nil
            && identity.appUrlScheme != nil
            && identity.claudeEntrypoint == "claude-vscode"
    }

    /// Never reached: this strategy always needs the session id.
    func focus(_ identity: TerminalIdentity) throws {
        throw FocusError.notFound
    }

    func focus(_ session: Session) throws {
        guard
            let scheme = session.terminal?.appUrlScheme,
            session.id.hasPrefix(Self.sessionIDPrefix)
        else {
            throw FocusError.notFound
        }

        let agentSessionID = String(session.id.dropFirst(Self.sessionIDPrefix.count))
        var components = URLComponents()
        components.scheme = scheme
        components.host = Self.extensionIdentifier
        components.path = "/open"
        components.queryItems = [URLQueryItem(name: "session", value: agentSessionID)]

        guard let url = components.url else {
            throw FocusError.notFound
        }

        guard NSWorkspace.shared.open(url) else {
            throw FocusError.notFound
        }
    }
}
