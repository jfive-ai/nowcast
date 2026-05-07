import Foundation
import GRDB

/// Owns the SQLite connection and the markdown-reports filesystem.
/// Single instance, created at app launch.
final class StorageManager {
    let dbQueue: DatabaseQueue

    init() throws {
        let dbURL = AppPaths.databaseURL
        var config = Configuration()
        config.foreignKeysEnabled = true
        self.dbQueue = try DatabaseQueue(path: dbURL.path, configuration: config)
        try Schema.migrator().migrate(dbQueue)
    }

    // MARK: - Reports

    func insertReport(_ report: Report, markdown: String) throws {
        let dayFolder = Self.dayFolder(for: report.generatedAt)
        let folderURL = AppPaths.reportsRoot.appendingPathComponent(dayFolder, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let fileURL = folderURL.appendingPathComponent("\(report.id.uuidString).md")
        try markdown.write(to: fileURL, atomically: true, encoding: .utf8)

        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let size = (attrs[.size] as? Int64) ?? Int64(markdown.utf8.count)
        let relativePath = "\(dayFolder)/\(report.id.uuidString).md"

        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO report
                  (id, preset_id, topic, window, generated_at, markdown_path, byte_size, source_count)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                    report.id.uuidString,
                    report.presetID?.uuidString,
                    report.topic,
                    report.window.rawValue,
                    report.generatedAt,
                    relativePath,
                    size,
                    report.sourceCount,
                ])
        }
    }

    func listReports() throws -> [Report] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, preset_id, topic, window, generated_at, markdown_path, byte_size, source_count
                FROM report
                ORDER BY generated_at DESC
                """).compactMap(Self.makeReport)
        }
    }

    func loadMarkdown(for report: Report) throws -> String {
        let url = AppPaths.reportURL(for: report.markdownPath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Total bytes used by markdown reports on disk.
    func totalReportBytes() throws -> Int64 {
        try dbQueue.read { db in
            try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(byte_size), 0) FROM report") ?? 0
        }
    }

    /// Delete the N oldest reports (DB row + markdown file). Returns count deleted.
    @discardableResult
    func deleteOldestReports(count: Int) throws -> Int {
        guard count > 0 else { return 0 }
        let oldest = try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, preset_id, topic, window, generated_at, markdown_path, byte_size, source_count
                FROM report
                ORDER BY generated_at ASC
                LIMIT ?
                """, arguments: [count]).compactMap(Self.makeReport)
        }
        try delete(reports: oldest)
        return oldest.count
    }

    /// Delete reports older than `cutoff`. Returns count deleted.
    @discardableResult
    func deleteReports(olderThan cutoff: Date) throws -> Int {
        let stale = try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, preset_id, topic, window, generated_at, markdown_path, byte_size, source_count
                FROM report
                WHERE generated_at < ?
                """, arguments: [cutoff]).compactMap(Self.makeReport)
        }
        try delete(reports: stale)
        return stale.count
    }

    private func delete(reports: [Report]) throws {
        for r in reports {
            let url = AppPaths.reportURL(for: r.markdownPath)
            try? FileManager.default.removeItem(at: url)
        }
        let ids = reports.map(\.id.uuidString)
        guard !ids.isEmpty else { return }
        try dbQueue.write { db in
            let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
            try db.execute(
                sql: "DELETE FROM report WHERE id IN (\(placeholders))",
                arguments: StatementArguments(ids)
            )
        }
    }

    // MARK: - Seen-item dedup

    /// Returns only items whose URL hashes haven't been recorded for this preset.
    /// Records the new hashes as a side effect.
    func filterUnseen(_ items: [RawItem], presetID: UUID?) throws -> [RawItem] {
        let presetKey = presetID?.uuidString
        return try dbQueue.write { db in
            var fresh: [RawItem] = []
            for item in items {
                let exists = try Bool.fetchOne(db, sql: """
                    SELECT 1 FROM seen_item WHERE preset_id IS ? AND url_hash = ? LIMIT 1
                    """, arguments: [presetKey, item.urlHash]) ?? false
                if !exists {
                    try db.execute(sql: """
                        INSERT OR IGNORE INTO seen_item (preset_id, url_hash, first_seen_at)
                        VALUES (?, ?, ?)
                        """, arguments: [presetKey, item.urlHash, Date()])
                    fresh.append(item)
                }
            }
            return fresh
        }
    }

    /// Prune `seen_item` rows older than 90 days (carryover from topic-pulse).
    func pruneSeenItems(olderThan days: Int = 90) throws {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM seen_item WHERE first_seen_at < ?",
                arguments: [cutoff]
            )
        }
    }

    // MARK: - Helpers

    private static func dayFolder(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f.string(from: date)
    }

    private static func makeReport(from row: Row) -> Report? {
        guard let idString: String = row["id"],
              let id = UUID(uuidString: idString),
              let topic: String = row["topic"],
              let windowRaw: String = row["window"],
              let window = TimeWindow(rawValue: windowRaw),
              let generatedAt: Date = row["generated_at"],
              let markdownPath: String = row["markdown_path"],
              let byteSize: Int64 = row["byte_size"],
              let sourceCount: Int = row["source_count"]
        else { return nil }

        let presetID: UUID? = (row["preset_id"] as String?).flatMap(UUID.init(uuidString:))

        return Report(
            id: id,
            presetID: presetID,
            topic: topic,
            window: window,
            generatedAt: generatedAt,
            markdownPath: markdownPath,
            byteSize: byteSize,
            sourceCount: sourceCount
        )
    }
}
