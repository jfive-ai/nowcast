import Foundation

/// Resolves filesystem paths the app uses. Under sandbox these resolve into
/// the app's container automatically — `FileManager` handles redirection.
enum AppPaths {
    /// Environment override for the support directory. Set by the headless
    /// self-check / CI so a regression run writes into a throwaway container
    /// instead of the user's real `~/Library/Application Support/Nowcast`.
    /// Never set in production.
    static let supportDirOverrideEnv = "NOWCAST_SUPPORT_DIR"

    static var supportDirectory: URL {
        let url: URL
        if let override = ProcessInfo.processInfo.environment[supportDirOverrideEnv],
           !override.isEmpty {
            url = URL(fileURLWithPath: override, isDirectory: true)
        } else if let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first {
            url = base.appendingPathComponent("Nowcast", isDirectory: true)
        } else {
            // Last-resort fallback so we never crash on a missing Application
            // Support directory (e.g. an exotic sandbox profile).
            url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("Nowcast", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var databaseURL: URL {
        supportDirectory.appendingPathComponent("nowcast.sqlite")
    }

    static var reportsRoot: URL {
        let url = supportDirectory.appendingPathComponent("reports", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Resolves a `report.markdownPath` (relative) to an absolute URL.
    static func reportURL(for relativePath: String) -> URL {
        reportsRoot.appendingPathComponent(relativePath)
    }
}
