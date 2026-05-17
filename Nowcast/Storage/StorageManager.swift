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
                       prompt_tokens, completion_tokens, usd_cost, model_used, provider_used, kind)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
                        report.kind.rawValue,
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
            providerUsed: report.providerUsed,
            kind: report.kind
        )
        return stored
    }

    func listReports() throws -> [Report] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, preset_id, topic, window, generated_at, markdown_path, byte_size, source_count, read_at,
                       prompt_tokens, completion_tokens, usd_cost, model_used, provider_used, kind
                FROM report
                ORDER BY generated_at DESC
                """).compactMap(Self.makeReport)
        }
    }

    /// Daily reports for a preset within the last `days` days, oldest-first.
    /// Used by the weekly synthesizer to build its input set.
    func dailyReports(forPreset presetID: UUID, withinDays days: Int = 7) throws -> [Report] {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        return try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, preset_id, topic, window, generated_at, markdown_path, byte_size, source_count, read_at,
                       prompt_tokens, completion_tokens, usd_cost, model_used, provider_used, kind
                FROM report
                WHERE preset_id = ? AND kind = 'daily' AND generated_at >= ?
                ORDER BY generated_at ASC
                """, arguments: [presetID.uuidString, cutoff]).compactMap(Self.makeReport)
        }
    }

    func updatePresetLastWeekly(id: UUID, at date: Date) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE topic_preset SET last_weekly_at = ? WHERE id = ?",
                arguments: [date, id.uuidString]
            )
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
                       prompt_tokens, completion_tokens, usd_cost, model_used, provider_used, kind
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
                       prompt_tokens, completion_tokens, usd_cost, model_used, provider_used, kind
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
                  (id, name, query, window, sources_json, cadence_json, delivery_json, created_at, last_run_at,
                   weekly_digest_enabled, last_weekly_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                  name = excluded.name,
                  query = excluded.query,
                  window = excluded.window,
                  sources_json = excluded.sources_json,
                  cadence_json = excluded.cadence_json,
                  delivery_json = excluded.delivery_json,
                  last_run_at = excluded.last_run_at,
                  weekly_digest_enabled = excluded.weekly_digest_enabled,
                  last_weekly_at = excluded.last_weekly_at
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
                    preset.weeklyDigestEnabled ? 1 : 0,
                    preset.lastWeeklyAt,
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
                SELECT id, name, query, window, sources_json, cadence_json, delivery_json, created_at, last_run_at,
                       weekly_digest_enabled, last_weekly_at
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

    // MARK: - Clusters / claims (v5)

    /// Persist the structured briefing result for a given report. Idempotent
    /// per report — calling twice replaces the prior set.
    func saveBriefing(_ result: BriefingResult, reportID: UUID) throws {
        try dbQueue.write { db in
            // Wipe and reinsert; ON DELETE CASCADE on `claim.cluster_id`
            // takes care of any stale child rows.
            try db.execute(
                sql: "DELETE FROM cluster WHERE report_id = ?",
                arguments: [reportID.uuidString]
            )
            for (idx, cluster) in result.clusters.enumerated() {
                let clusterUUID = UUID()
                let citationsJSON = (try? Self.encodeJSON(cluster.citations)) ?? "[]"
                try db.execute(sql: """
                    INSERT INTO cluster (id, report_id, headline, summary, ord, citations_json, counterpoint, gap)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [
                        clusterUUID.uuidString,
                        reportID.uuidString,
                        cluster.headline,
                        cluster.summary,
                        idx,
                        citationsJSON,
                        cluster.counterpoint,
                        cluster.gap,
                    ])
                for (cidx, claim) in cluster.claims.enumerated() {
                    let claimCitationsJSON = (try? Self.encodeJSON(claim.citations)) ?? "[]"
                    try db.execute(sql: """
                        INSERT INTO claim (id, cluster_id, text, citations_json, ord)
                        VALUES (?, ?, ?, ?, ?)
                        """, arguments: [
                            UUID().uuidString,
                            clusterUUID.uuidString,
                            claim.text,
                            claimCitationsJSON,
                            cidx,
                        ])
                }
            }
        }
    }

    func totalClusterCount() throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM cluster") ?? 0
        }
    }

    /// Load the clusters (+ claims) for a given report, ordered by `ord`.
    func clusters(for reportID: UUID) throws -> [BriefingResult.Cluster] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT id, headline, summary, ord, citations_json, counterpoint, gap
                FROM cluster
                WHERE report_id = ?
                ORDER BY ord ASC
                """, arguments: [reportID.uuidString])
            var out: [BriefingResult.Cluster] = []
            for row in rows {
                guard let cid: String = row["id"],
                      let headline: String = row["headline"],
                      let summary: String = row["summary"],
                      let citationsJSON: String = row["citations_json"]
                else { continue }
                let citations: [String] = (try? decodeJSON(citationsJSON)) ?? []
                let counterpoint: String? = row["counterpoint"]
                let gap: String? = row["gap"]
                let claimRows = try Row.fetchAll(db, sql: """
                    SELECT text, citations_json
                    FROM claim
                    WHERE cluster_id = ?
                    ORDER BY ord ASC
                    """, arguments: [cid])
                let claims: [BriefingResult.Claim] = claimRows.compactMap { r in
                    guard let text: String = r["text"],
                          let cj: String = r["citations_json"] else { return nil }
                    let cits: [String] = (try? decodeJSON(cj)) ?? []
                    return BriefingResult.Claim(text: text, citations: cits)
                }
                out.append(BriefingResult.Cluster(
                    id: cid,
                    headline: headline,
                    summary: summary,
                    claims: claims,
                    citations: citations,
                    counterpoint: counterpoint,
                    gap: gap
                ))
            }
            return out
        }
    }

    /// The most-recent earlier report for the given preset OR (if no preset)
    /// for the same topic string. Returns nil if no such report exists.
    func mostRecentPriorReport(presetID: UUID?, topic: String, before generatedAt: Date) throws -> Report? {
        try dbQueue.read { db in
            let row: Row?
            if let presetID {
                row = try Row.fetchOne(db, sql: """
                    SELECT id, preset_id, topic, window, generated_at, markdown_path, byte_size, source_count, read_at,
                           prompt_tokens, completion_tokens, usd_cost, model_used, provider_used, kind
                    FROM report
                    WHERE preset_id = ? AND generated_at < ?
                    ORDER BY generated_at DESC LIMIT 1
                    """, arguments: [presetID.uuidString, generatedAt])
            } else {
                row = try Row.fetchOne(db, sql: """
                    SELECT id, preset_id, topic, window, generated_at, markdown_path, byte_size, source_count, read_at,
                           prompt_tokens, completion_tokens, usd_cost, model_used, provider_used, kind
                    FROM report
                    WHERE preset_id IS NULL AND topic = ? AND generated_at < ?
                    ORDER BY generated_at DESC LIMIT 1
                    """, arguments: [topic, generatedAt])
            }
            return row.flatMap(Self.makeReport)
        }
    }

    // MARK: - Full-text search (v8)

    /// Re-index a report's row in `report_fts`. Idempotent — deletes any
    /// prior row for this report first.
    func indexReportForSearch(_ reportID: UUID, topic: String, body: String) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM report_fts WHERE report_id = ?",
                           arguments: [reportID.uuidString])
            try db.execute(sql: """
                INSERT INTO report_fts (report_id, topic, body)
                VALUES (?, ?, ?)
                """, arguments: [reportID.uuidString, topic, body])
        }
    }

    func indexItemsForSearch(_ items: [PersistedItem]) throws {
        guard !items.isEmpty else { return }
        try dbQueue.write { db in
            for item in items {
                try db.execute(sql: "DELETE FROM item_fts WHERE item_id = ?",
                               arguments: [item.id.uuidString])
                try db.execute(sql: """
                    INSERT INTO item_fts (item_id, title, snippet)
                    VALUES (?, ?, ?)
                    """, arguments: [item.id.uuidString, item.title, item.snippet ?? ""])
            }
        }
    }

    struct SearchHit: Hashable, Identifiable {
        let reportID: UUID
        let topic: String
        let snippet: String
        let kind: HitKind
        var id: String { "\(reportID.uuidString)-\(kind.rawValue)" }
        enum HitKind: String { case report, item }
    }

    func searchReports(_ query: String, limit: Int = 50) throws -> [SearchHit] {
        let cleaned = Self.sanitizeFTSQuery(query)
        guard !cleaned.isEmpty else { return [] }
        return try dbQueue.read { db in
            let reportRows = try Row.fetchAll(db, sql: """
                SELECT report_id, topic, snippet(report_fts, 2, '<<', '>>', '…', 12) AS snip
                FROM report_fts
                WHERE report_fts MATCH ?
                ORDER BY rank
                LIMIT ?
                """, arguments: [cleaned, limit])
            return reportRows.compactMap { r -> SearchHit? in
                guard let rid: String = r["report_id"], let uuid = UUID(uuidString: rid),
                      let topic: String = r["topic"]
                else { return nil }
                let snip: String = r["snip"] ?? ""
                return SearchHit(reportID: uuid, topic: topic, snippet: snip, kind: .report)
            }
        }
    }

    /// FTS5 punctuation can crash the query; escape user input and AND-join words.
    private static func sanitizeFTSQuery(_ query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let cleaned = trimmed.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }.reduce(into: "", { $0.append($1) })
        let tokens = cleaned
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return "" }
        // Quote each token to suppress FTS5 column-filter / operator parsing.
        return tokens.map { "\"\($0)\"" }.joined(separator: " AND ")
    }

    // MARK: - Source runs / health (v7)

    func recordSourceRun(_ run: SourceRun) throws {
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO source_run
                  (id, report_id, source_kind, started_at, finished_at,
                   items_returned, items_fresh, error_message)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                    run.id.uuidString,
                    run.reportID.uuidString,
                    run.sourceKind.rawValue,
                    run.startedAt,
                    run.finishedAt,
                    run.itemsReturned,
                    run.itemsFresh,
                    run.errorMessage,
                ])
        }
    }

    func sourceHealth(days: Int = 30) throws -> [SourceHealth] {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        return try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT source_kind,
                       COUNT(*) AS runs,
                       SUM(CASE WHEN error_message IS NULL THEN 1 ELSE 0 END) AS successes,
                       COALESCE(SUM(items_returned), 0) AS total_returned,
                       COALESCE(SUM(items_fresh), 0) AS total_fresh,
                       AVG(CASE WHEN finished_at IS NOT NULL
                                THEN (julianday(finished_at) - julianday(started_at)) * 86400.0
                                ELSE NULL END) AS avg_latency,
                       MAX(started_at) AS last_run_at
                FROM source_run
                WHERE started_at >= ?
                GROUP BY source_kind
                ORDER BY source_kind
                """, arguments: [cutoff])
            return rows.compactMap { row -> SourceHealth? in
                guard let kindRaw: String = row["source_kind"],
                      let kind = SourceKind(rawValue: kindRaw),
                      let runs: Int = row["runs"]
                else { return nil }
                let successes: Int = row["successes"] ?? 0
                let totalReturned: Int = row["total_returned"] ?? 0
                let totalFresh: Int = row["total_fresh"] ?? 0
                let avgLatency: Double? = row["avg_latency"]
                let lastRunAt: Date? = row["last_run_at"]

                let lastError: String? = (try? String.fetchOne(db, sql: """
                    SELECT error_message FROM source_run
                    WHERE source_kind = ? AND error_message IS NOT NULL
                    ORDER BY started_at DESC LIMIT 1
                    """, arguments: [kindRaw])) ?? nil

                return SourceHealth(
                    sourceKind: kind,
                    runs: runs,
                    successes: successes,
                    totalReturned: totalReturned,
                    totalFresh: totalFresh,
                    avgLatencySeconds: avgLatency,
                    lastError: lastError,
                    lastRunAt: lastRunAt
                )
            }
        }
    }

    // MARK: - Feedback (v6)

    func recordFeedback(_ feedback: Feedback) throws {
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO feedback (id, target, target_id, kind, note, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """, arguments: [
                    feedback.id.uuidString,
                    feedback.target.rawValue,
                    feedback.targetID,
                    feedback.kind.rawValue,
                    feedback.note,
                    feedback.createdAt,
                ])
        }
    }

    func deleteFeedback(target: Feedback.Target, targetID: String, kind: Feedback.Kind) throws {
        try dbQueue.write { db in
            try db.execute(sql: """
                DELETE FROM feedback
                WHERE target = ? AND target_id = ? AND kind = ?
                """, arguments: [target.rawValue, targetID, kind.rawValue])
        }
    }

    func feedback(target: Feedback.Target, targetID: String) throws -> [Feedback] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, target, target_id, kind, note, created_at
                FROM feedback
                WHERE target = ? AND target_id = ?
                ORDER BY created_at DESC
                """, arguments: [target.rawValue, targetID]).compactMap(Self.makeFeedback)
        }
    }

    /// Cluster IDs the user has explicitly starred. Used by the sidebar
    /// "Starred" entry.
    func starredClusterIDs() throws -> [String] {
        try dbQueue.read { db in
            try String.fetchAll(db, sql: """
                SELECT target_id FROM feedback
                WHERE target = 'cluster' AND kind = 'star'
                ORDER BY created_at DESC
                """)
        }
    }

    /// Headlines of clusters the user dismissed within the last `days` days,
    /// in newest-first order. Feeds the "avoid these themes" prompt hint.
    func recentDismissedHeadlines(days: Int = 30, limit: Int = 10) throws -> [String] {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        return try dbQueue.read { db in
            try String.fetchAll(db, sql: """
                SELECT c.headline FROM feedback f
                JOIN cluster c ON c.id = f.target_id
                WHERE f.target = 'cluster' AND f.kind IN ('dismiss', 'thumbs_down')
                  AND f.created_at >= ?
                ORDER BY f.created_at DESC LIMIT ?
                """, arguments: [cutoff, limit])
        }
    }

    // MARK: - Conversation (v9, P5-1)

    func insertConversationMessage(_ message: ConversationMessage) throws {
        let citationsJSON = (try? Self.encodeJSON(message.citations)) ?? "[]"
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO conversation_message
                  (id, report_id, role, text, citations_json, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """, arguments: [
                    message.id.uuidString,
                    message.reportID.uuidString,
                    message.role.rawValue,
                    message.text,
                    citationsJSON,
                    message.createdAt,
                ])
        }
    }

    func conversationMessages(forReport reportID: UUID) throws -> [ConversationMessage] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, report_id, role, text, citations_json, created_at
                FROM conversation_message
                WHERE report_id = ?
                ORDER BY created_at ASC
                """, arguments: [reportID.uuidString])
                .compactMap(Self.makeConversationMessage)
        }
    }

    func deleteConversation(forReport reportID: UUID) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM conversation_message WHERE report_id = ?",
                arguments: [reportID.uuidString]
            )
        }
    }

    func conversationMessageCount(forReport reportID: UUID) throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM conversation_message WHERE report_id = ?
                """, arguments: [reportID.uuidString]) ?? 0
        }
    }

    // MARK: - Entities (v10, P5-2)

    /// Upserts an entity by (canonical_name, kind). Returns the row's id —
    /// either the freshly-inserted one or the existing one.
    @discardableResult
    func upsertEntity(name: String, kind: Entity.Kind, at date: Date = Date()) throws -> UUID {
        try dbQueue.write { db in
            if let existingID: String = try String.fetchOne(db, sql: """
                SELECT id FROM entity
                WHERE canonical_name = ? AND kind = ?
                LIMIT 1
                """, arguments: [name, kind.rawValue]) {
                try db.execute(sql: """
                    UPDATE entity
                    SET last_seen_at = ?, mention_count = mention_count + 1
                    WHERE id = ?
                    """, arguments: [date, existingID])
                return UUID(uuidString: existingID) ?? UUID()
            } else {
                let newID = UUID()
                try db.execute(sql: """
                    INSERT INTO entity
                      (id, canonical_name, kind, first_seen_at, last_seen_at, mention_count)
                    VALUES (?, ?, ?, ?, ?, 1)
                    """, arguments: [
                        newID.uuidString,
                        name,
                        kind.rawValue,
                        date,
                        date,
                    ])
                return newID
            }
        }
    }

    /// Inserts a mention row. `INSERT OR IGNORE` because the natural key
    /// (entity, report, cluster) is the primary key — a duplicate just
    /// no-ops, which is exactly what we want when the extractor runs twice.
    func recordEntityMention(entityID: UUID, reportID: UUID, clusterID: String?) throws {
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT OR IGNORE INTO entity_mention (entity_id, report_id, cluster_id)
                VALUES (?, ?, ?)
                """, arguments: [
                    entityID.uuidString,
                    reportID.uuidString,
                    clusterID ?? "",
                ])
        }
    }

    /// Top-N entities ordered by mention count (desc), then last_seen.
    func topEntities(limit: Int = 50, kind: Entity.Kind? = nil) throws -> [Entity] {
        try dbQueue.read { db in
            let kindClause = kind.map { "WHERE kind = '\($0.rawValue)'" } ?? ""
            return try Row.fetchAll(db, sql: """
                SELECT id, canonical_name, kind, first_seen_at, last_seen_at, mention_count
                FROM entity
                \(kindClause)
                ORDER BY mention_count DESC, last_seen_at DESC
                LIMIT ?
                """, arguments: [limit]).compactMap(Self.makeEntity)
        }
    }

    /// Every report (with optional cluster headline) where this entity is mentioned.
    func mentions(forEntity entityID: UUID) throws -> [EntityTimelineRow] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT r.id, r.preset_id, r.topic, r.window, r.generated_at, r.markdown_path,
                       r.byte_size, r.source_count, r.read_at,
                       r.prompt_tokens, r.completion_tokens, r.usd_cost, r.model_used, r.provider_used, r.kind,
                       em.cluster_id AS cluster_id,
                       c.headline AS cluster_headline
                FROM entity_mention em
                JOIN report r ON r.id = em.report_id
                LEFT JOIN cluster c ON c.id = em.cluster_id
                WHERE em.entity_id = ?
                ORDER BY r.generated_at DESC
                """, arguments: [entityID.uuidString]).compactMap { row -> EntityTimelineRow? in
                    guard let report = Self.makeReport(from: row) else { return nil }
                    let clusterID: String? = {
                        let raw: String? = row["cluster_id"]
                        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        return trimmed.isEmpty ? nil : trimmed
                    }()
                    return EntityTimelineRow(
                        report: report,
                        clusterID: clusterID,
                        clusterHeadline: row["cluster_headline"]
                    )
                }
        }
    }

    func entityCount() throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entity") ?? 0
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

        let kindRaw: String = row["kind"] ?? "daily"
        let kind = Report.Kind(rawValue: kindRaw) ?? .daily

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
            providerUsed: providerUsed,
            kind: kind
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
        let weeklyEnabledInt: Int = row["weekly_digest_enabled"] ?? 0
        let lastWeekly: Date? = row["last_weekly_at"]

        return TopicPreset(
            id: id,
            name: name,
            query: query,
            window: window,
            sources: sources,
            cadence: cadence,
            deliveryChannels: delivery,
            createdAt: createdAt,
            lastRunAt: lastRun,
            weeklyDigestEnabled: weeklyEnabledInt != 0,
            lastWeeklyAt: lastWeekly
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

    private static func makeFeedback(from row: Row) -> Feedback? {
        guard let idString: String = row["id"],
              let id = UUID(uuidString: idString),
              let targetRaw: String = row["target"],
              let target = Feedback.Target(rawValue: targetRaw),
              let targetID: String = row["target_id"],
              let kindRaw: String = row["kind"],
              let kind = Feedback.Kind(rawValue: kindRaw),
              let createdAt: Date = row["created_at"]
        else { return nil }
        return Feedback(
            id: id,
            target: target,
            targetID: targetID,
            kind: kind,
            note: row["note"],
            createdAt: createdAt
        )
    }

    private static func makeEntity(from row: Row) -> Entity? {
        guard let idString: String = row["id"],
              let id = UUID(uuidString: idString),
              let name: String = row["canonical_name"],
              let kindRaw: String = row["kind"],
              let kind = Entity.Kind(rawValue: kindRaw),
              let firstSeen: Date = row["first_seen_at"],
              let lastSeen: Date = row["last_seen_at"],
              let mentions: Int = row["mention_count"]
        else { return nil }
        return Entity(
            id: id,
            canonicalName: name,
            kind: kind,
            firstSeenAt: firstSeen,
            lastSeenAt: lastSeen,
            mentionCount: mentions
        )
    }

    private static func makeConversationMessage(from row: Row) -> ConversationMessage? {
        guard let idString: String = row["id"],
              let id = UUID(uuidString: idString),
              let reportIDString: String = row["report_id"],
              let reportID = UUID(uuidString: reportIDString),
              let roleRaw: String = row["role"],
              let role = ConversationMessage.Role(rawValue: roleRaw),
              let text: String = row["text"],
              let createdAt: Date = row["created_at"]
        else { return nil }
        let citationsJSON: String = row["citations_json"] ?? "[]"
        let citations: [String] = (try? Self.decodeJSON(citationsJSON)) ?? []
        return ConversationMessage(
            id: id,
            reportID: reportID,
            role: role,
            text: text,
            citations: citations,
            createdAt: createdAt
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

    private func decodeJSON<T: Decodable>(_ json: String) throws -> T {
        try Self.decodeJSON(json)
    }
}
