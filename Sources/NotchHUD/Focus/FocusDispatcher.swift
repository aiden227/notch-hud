import Foundation

@MainActor
final class FocusDispatcher {
    private let strategies: [any FocusStrategy]

    init(strategies: [any FocusStrategy] = [
        TerminalAppStrategy(),
        ITerm2Strategy(),
        WezTermStrategy(),
        KittyStrategy(),
        // Editor-hosted sessions: deep-link to the exact tab when we can,
        // otherwise fall back to merely raising the host application.
        EditorSessionStrategy(),
        ApplicationStrategy()
    ]) {
        self.strategies = strategies
    }

    func focus(_ session: Session) async -> Result<Void, FocusError> {
        guard let identity = session.terminal,
              let strategy = strategies.first(where: { $0.canHandle(identity) })
        else {
            return .failure(.notFound)
        }

        do {
            try await Task.detached {
                try strategy.focus(session)
            }.value
            return .success(())
        } catch let error as FocusError {
            return .failure(error)
        } catch {
            return .failure(.scriptFailed(error.localizedDescription))
        }
    }
}
