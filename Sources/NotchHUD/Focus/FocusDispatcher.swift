import Foundation

@MainActor
final class FocusDispatcher {
    private let strategies: [any FocusStrategy]

    init(strategies: [any FocusStrategy] = [
        TerminalAppStrategy(),
        ITerm2Strategy(),
        WezTermStrategy(),
        KittyStrategy(),
        // Last: only handles what the tty-based strategies decline.
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
                try strategy.focus(identity)
            }.value
            return .success(())
        } catch let error as FocusError {
            return .failure(error)
        } catch {
            return .failure(.scriptFailed(error.localizedDescription))
        }
    }
}
