import Foundation

@MainActor
final class StalenessSweeper {
    private let spoolURL: URL
    private let store: SessionStore
    private let workingStaleSeconds: TimeInterval
    private let dropSeconds: TimeInterval
    private let fileManager: FileManager
    private var timer: Timer?

    init(
        spoolURL: URL,
        store: SessionStore,
        workingStaleSeconds: TimeInterval = 90,
        dropSeconds: TimeInterval = 15 * 60,
        fileManager: FileManager = .default
    ) {
        self.spoolURL = spoolURL
        self.store = store
        self.workingStaleSeconds = workingStaleSeconds
        self.dropSeconds = dropSeconds
        self.fileManager = fileManager
    }

    func start() {
        guard timer == nil else { return }

        sweep()
        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sweep()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func sweep(now: Date = Date()) {
        var sessions = store.sessionsWithoutPendingOverlay
        var deletedSessionIDs = Set<String>()
        var didChangeStore = false

        for index in sessions.indices {
            let age = now.timeIntervalSince(sessions[index].updatedAt)

            if age > workingStaleSeconds,
               (sessions[index].status == .working || sessions[index].status == .starting) {
                sessions[index].status = .unknown
                didChangeStore = true
            }

            // Purge finished sessions we could never take the user to anyway —
            // launchd jobs and other background agents. An editor-hosted session
            // has no tty either, but IS focusable via its app's URI handler, so
            // dropping it on sight would delete the "done" row before it could be
            // seen. Those age out through dropSeconds like everything else.
            let isUnreachable = sessions[index].terminal?.tty == nil
                && sessions[index].terminal?.appBundleId == nil
            let isBackgroundAndFinished = isUnreachable
                && (sessions[index].status == .done || sessions[index].status == .unknown)
            if age > dropSeconds || isBackgroundAndFinished {
                removeSpoolFile(for: sessions[index].id)
                deletedSessionIDs.insert(sessions[index].id)
                didChangeStore = true
            }
        }

        if !deletedSessionIDs.isEmpty {
            sessions.removeAll { deletedSessionIDs.contains($0.id) }
        }

        if didChangeStore {
            store.apply(sessions)
        }
    }

    private func removeSpoolFile(for sessionID: String) {
        guard !sessionID.isEmpty,
              !sessionID.contains("/"),
              sessionID != ".",
              sessionID != ".."
        else {
            return
        }

        let fileURL = spoolURL.appendingPathComponent("\(sessionID).json", isDirectory: false)
        try? fileManager.removeItem(at: fileURL)
    }
}
