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

    func insertReport(_ report: Report, markdown: String) throws -> Report {
        let dayFolder = Self.dayFolder(for: report.generatedAt)
        let folderURL = AppPaths.reportsRoot.appendingPathComponent(dayFolder, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let fileURL = folderURL.appendingPathComponent("\(report.id.uuidString).md")
        try markdown.write(to: fileURL, atomically: true, encoding: .utf8)

        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let size = (attrs[.size] as? Int64) ?? Int64(markdown.utf8.count)
        let relativePath = "\(dayFolder)/\(report.id.uuidString).md"

        do {
            try dbQueue.write { db in
                try db.execute(sql: """
                    INSERT INTO report
                      (id, preset_id, topic, window, generated_at, markdown_path, byte_size, source_count, read_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [
                        report.id.uuidString,
                        report.presetID?.uuidString,
                        report.topic,
                        report.window.rawValue,
                        report.generatedAt,
                        relativePath,
                        size,
                        report.sourceCount,
                        report.readAt,
                    ])
            }
        } catch {
            // DB write failed — clean up the orphan markdown file before rethrowing.
            try? FileManager.default.removeItem(at: fileURL)
            throw error
        }

        var stored = report
        stored = Report(
            id: report.id,
            presetID: report.presetID,
            topic: report.topic,
            window: report.window,
            generatedAt: report.generatedAt,
            markdownPath: relativePath,
            byteSize: size,
            sourceCount: report.sourceCount,
            readAt: report.readAt
        )
        return stored
    }

    func listReports() throws -> [Report] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, preset_id, topic, window, generated_at, markdown_path, byte_size, source_count, read_at
                FROM report
                ORDER BY generated_at DESC
                """).compactMap(Self.makeReport)
        }
    }

    func loadMarkdown(for report: Report) throws -> String {
        let url = AppPaths.reportURL(for: report.markdownPath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    func markRead(reportID: UUID, at date: Date = Date()) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE report SET read_at = ? WHERE id = ? AND read_at IS NULL",
                arguments: [date, reportID.uuidString]
            )
        }
    }

    func unreadCount() throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM report WHERE read_at IS NULL") ?? 0
        }
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
                SELECT id, preset_id, topic, window, generated_at, markdown_path, byte_size, source_count, read_at
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
                SELECT id, preset_id, topic, window, generated_at, markdown_path, byte_size, source_count, read_at
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

    // MARK: - Topic presets

    func upsertPreset(_ preset: TopicPreset) throws {
        let sourcesJSON = try Self.encodeJSON(preset.sources)
        let cadenceJSON = try Self.encodeJSON(preset.cadence)
        let deliveryJSON = try Self.encodeJSON(preset.deliveryChannels)

        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO topic_preset
                  (id, name, query, window, sources_json, cadence_json, delivery_json, created_at, last_run_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                  name = excluded.name,
                  query = excluded.query,
                  window = excluded.window,
                  sources_json = excluded.sources_json,
                  cadence_json = excluded.cadence_json,
                  delivery_json = excluded.delivery_json,
                  last_run_at = excluded.last_run_at
                """, arguments: [
                    preset.id.uuidString,
                    preset.name,
                    preset.query,
                    preset.window.rawValue,
                    sourcesJSON,
                    cadenceJSON,
                    deliveryJSON,
                    preset.createdAt,
                    preset.lastRunAt,
                ])
        }
    }

    func deletePreset(id: UUID) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM topic_preset WHERE id = ?",
                arguments: [id.uuidString]
            )
        }
    }

    func listPresets() throws -> [TopicPreset] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, name, query, window, sources_json, cadence_json, delivery_json, created_at, last_run_at
                FROM topic_preset
                ORDER BY created_at ASC
                """).compactMap(Self.makePreset)
        }
    }

    func updatePresetLastRun(id: UUID, at date: Date) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE topic_preset SET last_run_at = ? WHERE id = ?",
                arguments: [date, id.uuidString]
            )
        }
    }

    // MARK: - Seen-item dedup

    /// Returns only items whose URL hashes haven't been recorded for this preset.
    /// Hashes are NOT recorded here — the caller should call
    /// `recordSeen(_:presetID:)` after a successful LLM/persist round-trip,
    /// so a network failure doesn't permanently blacklist items.
    func filterUnseen(_ items: [RawItem], presetID: UUID?) throws -> [RawItem] {
        let presetKey = presetID?.uuidString
        return try dbQueue.read { db in
            var fresh: [RawItem] = []
            for item in items {
                let exists = try Bool.fetchOne(db, sql: """
                    SELECT 1 FROM seen_item WHERE preset_id IS ? AND url_hash = ? LIMIT 1
                    """, arguments: [presetKey, item.urlHash]) ?? false
                if !exists { fresh.append(item) }
            }
            return fresh
        }
    }

    /// Record the given items as "seen" for this preset. Call after a
    /// report has been successfully written.
    func recordSeen(_ items: [RawItem], presetID: UUID?) throws {
        guard !items.isEmpty else { return }
        let presetKey = presetID?.uuidString
        let now = Date()
        try dbQueue.write { db in
            for item in items {
                try db.execute(sql: """
                    INSERT OR IGNORE INTO seen_item (preset_id, url_hash, first_seen_at)
                    VALUES (?, ?, ?)
                    """, arguments: [presetKey, item.urlHash, now])
            }
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
        let readAt: Date? = row["read_at"]

        return Report(
            id: id,
            presetID: presetID,
            topic: topic,
            window: window,
            generatedAt: generatedAt,
            markdownPath: markdownPath,
            byteSize: byteSize,
            sourceCount: sourceCount,
            readAt: readAt
        )
    }

    private static func makePreset(from row: Row) -> TopicPreset? {
        guard let idString: String = row["id"],
              let id = UUID(uuidString: idString),
              let name: String = row["name"],
              let query: String = row["query"],
              let windowRaw: String = row["window"],
              let window = TimeWindow(rawValue: windowRaw),
              let sourcesJSON: String = row["sources_json"],
              let cadenceJSON: String = row["cadence_json"],
              let deliveryJSON: String = row["delivery_json"],
              let createdAt: Date = row["created_at"]
        else { return nil }

        let sources: [SourceKind] = (try? decodeJSON(sourcesJSON)) ?? []
        let cadence: Cadence = (try? decodeJSON(cadenceJSON)) ?? .manual
        let delivery: [DeliveryChannel] = (try? decodeJSON(deliveryJSON)) ?? [.inApp]
        let lastRun: Date? = row["last_run_at"]

        return TopicPreset(
            id: id,
            name: name,
            query: query,
            window: window,
            sources: sources,
            cadence: cadence,
            deliveryChannels: delivery,
            createdAt: createdAt,
            lastRunAt: lastRun
        )
    }

    private static func encodeJSON<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(decoding: data, as: UTF8.self)
    }

    private static func decodeJSON<T: Decodable>(_ json: String) throws -> T {
        let data = Data(json.utf8)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
