import Foundation

/// Path handling for spool files.
///
/// The id comes from a hook payload, so it is untrusted input that gets turned
/// into a filesystem path. The guards live here so every deletion site shares
/// them rather than re-implementing them.
enum SpoolFile {
    static func url(for sessionID: String, in spoolURL: URL) -> URL? {
        guard
            !sessionID.isEmpty,
            !sessionID.contains("/"),
            sessionID != ".",
            sessionID != ".."
        else {
            return nil
        }
        return spoolURL.appendingPathComponent("\(sessionID).json", isDirectory: false)
    }

    static func remove(
        sessionID: String,
        in spoolURL: URL,
        fileManager: FileManager = .default
    ) {
        guard let fileURL = url(for: sessionID, in: spoolURL) else { return }
        try? fileManager.removeItem(at: fileURL)
    }
}
