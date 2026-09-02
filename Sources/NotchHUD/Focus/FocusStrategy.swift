protocol FocusStrategy: Sendable {
    func canHandle(_ identity: TerminalIdentity) -> Bool
    func focus(_ identity: TerminalIdentity) throws

    /// Overridden only by strategies that need more than the terminal identity —
    /// deep-linking to an editor session needs the session id too. Everything
    /// else inherits the default and keeps working off the identity alone.
    func focus(_ session: Session) throws
}

extension FocusStrategy {
    func focus(_ session: Session) throws {
        guard let identity = session.terminal else {
            throw FocusError.notFound
        }
        try focus(identity)
    }
}

enum FocusError: Error {
    case notFound
    case permissionDenied(String)
    case scriptFailed(String)
}
