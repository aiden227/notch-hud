struct TerminalIdentity: Codable, Sendable {
    let termProgram: String?
    let tty: String?
    let itermSessionId: String?
    let weztermPane: String?
    let kittyWindowId: String?
    let windowId: String?
    /// Bundle identifier of the GUI application hosting the session, recorded
    /// for sessions with no controlling tty (Claude Code inside an editor).
    let appBundleId: String?
    /// Human-readable name of that application, for the row's tooltip.
    let appName: String?
    /// First URL scheme the host application registers, used to deep-link to a
    /// specific session rather than merely raising the app.
    let appUrlScheme: String?
    /// `CLAUDE_CODE_ENTRYPOINT` as inherited by the hook — "claude-vscode" when
    /// the session is running inside a VS Code-family editor.
    let claudeEntrypoint: String?
}
