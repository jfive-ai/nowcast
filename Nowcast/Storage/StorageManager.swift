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
                      (id, preset_id, topic, window, generated_at, markdown_path, byte_size, source_count, read_at,
                       prompt_tokens, completion_tokens, usd_cost, model_used, provider_used)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
                        report.promptTokens,
                        report.completionTokens,
                        report.usdCost,
                        report.modelUsed,
                        report.providerUsed,
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
            readAt: report.readAt,
            promptTokens: report.promptTokens,
            completionTokens: report.completionTokens,
            usdCost: report.usdCost,
            modelUsed: report.modelUsed,
            providerUsed: report.providerUsed
        )
        return stored
    }

    func listReports() throws -> [Report] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, preset_id, topic, window, generated_at, markdown_path, byte_size, source_count, read_at,
                       prompt_tokens, completion_tokens, usd_cost, model_used, provider_used
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

    /// Delete the N oldest reports (DB row + markdown file). Returns the
    /// deleted IDs so callers can mirror the change in side indexes
    /// (Spotlight, etc.).
    @discardableResult
    func deleteOldestReports(count: Int) throws -> [UUID] {
        guard count > 0 else { return [] }
        let oldest = try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, preset_id, topic, window, generated_at, markdown_path, byte_size, source_count, read_at,
                       prompt_tokens, completion_tokens, usd_cost, model_used, provider_used
                FROM report
                ORDER BY generated_at ASC
                LIMIT ?
                """, arguments: [count]).compactMap(Self.makeReport)
        }
        try delete(reports: oldest)
        return oldest.map(\.id)
    }

    /// Delete reports older than `cutoff`. Returns the deleted IDs.
    @discardableResult
    func deleteReports(olderThan cutoff: Date) throws -> [UUID] {
        let stale = try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, preset_id, topic, window, generated_at, markdown_path, byte_size, source_count, read_at,
                       prompt_tokens, completion_tokens, usd_cost, model_used, provider_used
                FROM report
                WHERE generated_at < ?
                """, arguments: [cutoff]).compactMap(Self.makeReport)
        }
        try delete(reports: stale)
        return stale.map(\.id)
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

    // MARK: - Source subscriptions

    func upsertSubscription(_ sub: SourceSubscription) throws {
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO source_subscription (id, kind, identifier, label)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                  kind = excluded.kind,
                  identifier = excluded.identifier,
                  label = excluded.label
                """, arguments: [
                    sub.id.uuidString,
                    sub.kind.rawValue,
                    sub.identifier,
                    sub.label,
                ])
        }
    }

    func deleteSubscription(id: UUID) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM source_subscription WHERE id = ?",
                arguments: [id.uuidString]
            )
        }
    }

    func listSubscriptions() throws -> [SourceSubscription] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, kind, identifier, label
                FROM source_subscription
                ORDER BY label ASC
                """).compactMap(Self.makeSubscription)
        }
    }

    // MARK: - Persisted items (v4)

    /// Insert any of `items` whose `url_hash` isn't already present, and
    /// return the canonical row IDs (existing or new) keyed by `url_hash`.
    @discardableResult
    func upsertItems(_ items: [RawItem]) throws -> [String: UUID] {
        guard !items.isEmpty else { return [:] }
        return try dbQueue.write { db in
            var result: [String: UUID] = [:]
            for raw in items {
                let persisted = PersistedItem(from: raw)
                if let existing = try Row.fetchOne(db,
                    sql: "SELECT id FROM item WHERE url_hash = ? LIMIT 1",
                    arguments: [persisted.urlHash]) {
                    if let idString: String = existing["id"], let uuid = UUID(uuidString: idString) {
                        result[persisted.urlHash] = uuid
                    }
                    continue
                }
                try db.execute(sql: """
                    INSERT INTO item
                      (id, canonical_url, url_hash, title, snippet, transcript,
                       source_kind, author, published_at, first_seen_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [
                        persisted.id.uuidString,
                        persisted.canonicalURL.absoluteString,
                        persisted.urlHash,
                        persisted.title,
                        persisted.snippet,
                        persisted.transcript,
                        persisted.sourceKind.rawValue,
                        persisted.author,
                        persisted.publishedAt,
                        persisted.firstSeenAt,
                    ])
                result[persisted.urlHash] = persisted.id
            }
            return result
        }
    }

    /// Link each item to a report. `freshHashes` are the items that did NOT
    /// appear in any earlier report — they get `is_fresh = 1`; everything
    /// else is `is_fresh = 0` (context items surfaced again).
    func attachItemsToReport(_ reportID: UUID,
                             itemIDsByHash: [String: UUID],
                             freshHashes: Set<String>) throws {
        guard !itemIDsByHash.isEmpty else { return }
        try dbQueue.write { db in
            for (hash, itemID) in itemIDsByHash {
                let isFresh = freshHashes.contains(hash) ? 1 : 0
                try db.execute(sql: """
                    INSERT OR IGNORE INTO report_item (report_id, item_id, is_fresh)
                    VALUES (?, ?, ?)
                    """, arguments: [reportID.uuidString, itemID.uuidString, isFresh])
            }
        }
    }

    /// Items linked to a given report, ordered by source kind then title.
    func itemsForReport(_ reportID: UUID) throws -> [PersistedItem] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT i.id, i.canonical_url, i.url_hash, i.title, i.snippet, i.transcript,
                       i.source_kind, i.author, i.published_at, i.first_seen_at
                FROM item i
                JOIN report_item ri ON ri.item_id = i.id
                WHERE ri.report_id = ?
                ORDER BY i.source_kind ASC, i.title ASC
                """, arguments: [reportID.uuidString]).compactMap(Self.makePersistedItem)
        }
    }

    /// Total persisted-item count. Used by the Settings debug readout.
    func totalItemCount() throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM item") ?? 0
        }
    }

    /// Total report-item link count. Used by the Settings debug readout.
    func totalReportItemCount() throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM report_item") ?? 0
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
        let promptTokens: Int? = row["prompt_tokens"]
        let completionTokens: Int? = row["completion_tokens"]
        let usdCost: Double? = row["usd_cost"]
        let modelUsed: String? = row["model_used"]
        let providerUsed: String? = row["provider_used"]

        return Report(
            id: id,
            presetID: presetID,
            topic: topic,
            window: window,
            generatedAt: generatedAt,
            markdownPath: markdownPath,
            byteSize: byteSize,
            sourceCount: sourceCount,
            readAt: readAt,
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            usdCost: usdCost,
            modelUsed: modelUsed,
            providerUsed: providerUsed
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

    private static func makePersistedItem(from row: Row) -> PersistedItem? {
        guard let idString: String = row["id"],
              let id = UUID(uuidString: idString),
              let canonicalString: String = row["canonical_url"],
              let canonical = URL(string: canonicalString),
              let urlHash: String = row["url_hash"],
              let title: String = row["title"],
              let sourceKindRaw: String = row["source_kind"],
              let sourceKind = SourceKind(rawValue: sourceKindRaw),
              let firstSeenAt: Date = row["first_seen_at"]
        else { return nil }
        return PersistedItem(
            id: id,
            canonicalURL: canonical,
            urlHash: urlHash,
            title: title,
            snippet: row["snippet"],
            transcript: row["transcript"],
            sourceKind: sourceKind,
            author: row["author"],
            publishedAt: row["published_at"],
            firstSeenAt: firstSeenAt
        )
    }

    private static func makeSubscription(from row: Row) -> SourceSubscription? {
        guard let idString: String = row["id"],
              let id = UUID(uuidString: idString),
              let kindRaw: String = row["kind"],
              let kind = SourceKind(rawValue: kindRaw),
              let identifier: String = row["identifier"],
              let label: String = row["label"]
        else { return nil }
        return SourceSubscription(id: id, kind: kind, identifier: identifier, label: label)
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
