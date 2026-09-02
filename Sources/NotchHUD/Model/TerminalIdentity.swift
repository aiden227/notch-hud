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
}
