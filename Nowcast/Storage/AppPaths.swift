import Foundation

/// Resolves filesystem paths the app uses. Under sandbox these resolve into
/// the app's container automatically — `FileManager` handles redirection.
enum AppPaths {
    static var supportDirectory: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        let url = base.appendingPathComponent("Nowcast", isDirectory: true)
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
