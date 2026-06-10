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
                       prompt_tokens, completion_tokens, usd_cost, model_used, provider_used, kind, title,
                       big_story_score, big_story_headline, sentiment, sentiment_rationale)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
                        report.title,
                        report.bigStoryScore,
                        report.bigStoryHeadline,
                        report.sentiment,
                        report.sentimentRationale,
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
            kind: report.kind,
            title: report.title,
            bigStoryScore: report.bigStoryScore,
            bigStoryHeadline: report.bigStoryHeadline,
            sentiment: report.sentiment,
            sentimentRationale: report.sentimentRationale
        )
        return stored
    }

    func listReports() throws -> [Report] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, preset_id, topic, window, generated_at, markdown_path, byte_size, source_count, read_at,
                       prompt_tokens, completion_tokens, usd_cost, model_used, provider_used, kind, title,
                       big_story_score, big_story_headline, sentiment, sentiment_rationale
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
                       prompt_tokens, completion_tokens, usd_cost, model_used, provider_used, kind, title,
                       big_story_score, big_story_headline, sentiment, sentiment_rationale
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
                       prompt_tokens, completion_tokens, usd_cost, model_used, provider_used, kind, title,
                       big_story_score, big_story_headline, sentiment, sentiment_rationale
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
                       prompt_tokens, completion_tokens, usd_cost, model_used, provider_used, kind, title,
                       big_story_score, big_story_headline, sentiment, sentiment_rationale
                FROM report
                WHERE generated_at < ?
                """, arguments: [cutoff]).compactMap(Self.makeReport)
        }
        try delete(reports: stale)
        return stale.map(\.id)
    }

    /// Most-recent report ID, if any. Used as a synthetic anchor for
    /// source-health rows on noFreshItems runs.
    func mostRecentReportID() throws -> UUID? {
        try dbQueue.read { db in
            guard let s: String = try String.fetchOne(db,
                sql: "SELECT id FROM report ORDER BY generated_at DESC LIMIT 1")
            else { return nil }
            return UUID(uuidString: s)
        }
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
            // Purge FTS shadow rows when their parent report is deleted,
            // otherwise search returns stale hits whose detail view would
            // be empty.
            try db.execute(
                sql: "DELETE FROM report_fts WHERE report_id IN (\(placeholders))",
                arguments: StatementArguments(ids)
            )
            // Items belonging only to deleted reports should also be
            // pruned from item_fts. Items remain in `item` (cascade
            // doesn't cover the FTS table), so we drop their FTS rows
            // when the join leaves no parent report.
            try db.execute(sql: """
                DELETE FROM item_fts
                WHERE item_id IN (
                    SELECT i.id FROM item i
                    WHERE NOT EXISTS (
                        SELECT 1 FROM report_item ri WHERE ri.item_id = i.id
                    )
                )
                """)
            try db.execute(
                sql: "DELETE FROM report WHERE id IN (\(placeholders))",
                arguments: StatementArguments(ids)
            )
        }
    }

    /// Re-populate `report_fts` and `item_fts` from the canonical tables
    /// when those FTS tables are detected to be out of sync (e.g. after a
    /// fresh migration or after a bug emptied them). Idempotent. Also
    /// covers reports that pre-existed the v8 migration so they're
    /// searchable immediately.
    func backfillFullTextIndexIfNeeded() throws {
        // Phase 1: discover what needs backfilling (read-only).
        struct PendingReport { let id: String; let topic: String; let path: String }
        struct PendingItem { let id: String; let title: String; let snippet: String }
        let (pendingReports, pendingItems) = try dbQueue.read { db -> ([PendingReport], [PendingItem]) in
            let reportRows = try Row.fetchAll(db, sql: """
                SELECT id, topic, markdown_path FROM report
                WHERE id NOT IN (SELECT report_id FROM report_fts)
                """)
            let pr: [PendingReport] = reportRows.compactMap {
                guard let id: String = $0["id"],
                      let topic: String = $0["topic"],
                      let path: String = $0["markdown_path"]
                else { return nil }
                return PendingReport(id: id, topic: topic, path: path)
            }
            let itemRows = try Row.fetchAll(db, sql: """
                SELECT id, title, snippet FROM item
                WHERE id NOT IN (SELECT item_id FROM item_fts)
                """)
            let pi: [PendingItem] = itemRows.compactMap {
                guard let id: String = $0["id"], let title: String = $0["title"] else { return nil }
                let snippet: String = $0["snippet"] ?? ""
                return PendingItem(id: id, title: title, snippet: snippet)
            }
            return (pr, pi)
        }
        guard !pendingReports.isEmpty || !pendingItems.isEmpty else { return }

        // Phase 2: read markdown files OUTSIDE the write transaction —
        // file-IO errors here are recoverable (we just use an empty body)
        // and shouldn't roll back the entire transaction.
        let reportBodies: [(id: String, topic: String, body: String)] =
            pendingReports.map { pr in
                let url = AppPaths.reportURL(for: pr.path)
                let body = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                return (pr.id, pr.topic, body)
            }

        // Phase 3: write in a single transaction.
        try dbQueue.write { db in
            for r in reportBodies {
                try db.execute(sql: """
                    INSERT INTO report_fts (report_id, topic, body)
                    VALUES (?, ?, ?)
                    """, arguments: [r.id, r.topic, r.body])
            }
            for p in pendingItems {
                try db.execute(sql: """
                    INSERT INTO item_fts (item_id, title, snippet)
                    VALUES (?, ?, ?)
                    """, arguments: [p.id, p.title, p.snippet])
            }
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
                // Persist the cluster id the briefing emitted (the same
                // `c1`/`c2`/… downstream extractors reference) so
                // entity_mention.cluster_id joins back to cluster.id —
                // scoped by report so ids can't collide across reports.
                let persistedID = "\(reportID.uuidString):\(cluster.id)"
                let citationsJSON = (try? Self.encodeJSON(cluster.citations)) ?? "[]"
                try db.execute(sql: """
                    INSERT INTO cluster (id, report_id, headline, summary, ord, citations_json, counterpoint, gap)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [
                        persistedID,
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
                            persistedID,
                            claim.text,
                            claimCitationsJSON,
                            cidx,
                        ])
                }
            }
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
                           prompt_tokens, completion_tokens, usd_cost, model_used, provider_used, kind, title
                    FROM report
                    WHERE preset_id = ? AND generated_at < ?
                    ORDER BY generated_at DESC LIMIT 1
                    """, arguments: [presetID.uuidString, generatedAt])
            } else {
                row = try Row.fetchOne(db, sql: """
                    SELECT id, preset_id, topic, window, generated_at, markdown_path, byte_size, source_count, read_at,
                           prompt_tokens, completion_tokens, usd_cost, model_used, provider_used, kind, title
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
            // Search both `report_fts` AND `item_fts` so terms that only
            // appear in item titles/snippets still match. JOIN against
            // `report` so deleted reports whose FTS shadow rows weren't
            // purged don't appear as ghost hits.
            let reportRows = try Row.fetchAll(db, sql: """
                SELECT f.report_id AS report_id,
                       r.topic AS topic,
                       snippet(report_fts, 2, '<<', '>>', '…', 12) AS snip
                FROM report_fts f
                JOIN report r ON r.id = f.report_id
                WHERE f.report_fts MATCH ?
                ORDER BY rank
                LIMIT ?
                """, arguments: [cleaned, limit])
            var hits: [SearchHit] = []
            var seen = Set<UUID>()
            for r in reportRows {
                guard let rid: String = r["report_id"],
                      let uuid = UUID(uuidString: rid),
                      let topic: String = r["topic"]
                else { continue }
                seen.insert(uuid)
                let snip: String = r["snip"] ?? ""
                hits.append(SearchHit(reportID: uuid, topic: topic, snippet: snip, kind: .report))
            }
            // Item-side: find items whose title/snippet matches, then
            // bring along the report they were attached to. Excludes
            // reports already matched on the report side.
            let itemRows = try Row.fetchAll(db, sql: """
                SELECT DISTINCT ri.report_id AS report_id,
                       r.topic AS topic,
                       snippet(item_fts, 1, '<<', '>>', '…', 12) AS snip
                FROM item_fts
                JOIN report_item ri ON ri.item_id = item_fts.item_id
                JOIN report r       ON r.id = ri.report_id
                WHERE item_fts MATCH ?
                LIMIT ?
                """, arguments: [cleaned, limit])
            for r in itemRows {
                guard let rid: String = r["report_id"],
                      let uuid = UUID(uuidString: rid),
                      !seen.contains(uuid),
                      let topic: String = r["topic"]
                else { continue }
                seen.insert(uuid)
                let snip: String = r["snip"] ?? ""
                hits.append(SearchHit(reportID: uuid, topic: topic, snippet: snip, kind: .item))
            }
            return Array(hits.prefix(limit))
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

    // MARK: - Embeddings (v14)

    /// Persist a per-report sentence embedding as a Float32 LE BLOB.
    /// Idempotent — overwrites any prior vector for the same report.
    func saveEmbedding(reportID: UUID, vector: [Float]) throws {
        let blob = ReportEmbedder.encode(vector)
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE report SET embedding = ? WHERE id = ?",
                arguments: [blob, reportID.uuidString]
            )
        }
    }

    /// (reportID, vector) for every report that has a stored embedding.
    /// Used by semantic search at query time (in-memory cosine scan).
    func allEmbeddings() throws -> [(reportID: UUID, vector: [Float])] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, embedding FROM report
                WHERE embedding IS NOT NULL
                """).compactMap { row -> (UUID, [Float])? in
                    guard let idString: String = row["id"],
                          let id = UUID(uuidString: idString),
                          let blob: Data = row["embedding"],
                          let vector = ReportEmbedder.decode(blob)
                    else { return nil }
                    return (id, vector)
                }
        }
    }

    /// Report rows that need an embedding — used by the launch-time
    /// backfill so historical briefs become semantically searchable on
    /// the next launch after upgrade. Returns the markdown path so the
    /// caller can read the body outside the read transaction.
    struct EmbeddingBackfillRow { let id: UUID; let topic: String; let title: String?; let markdownPath: String }

    func reportsMissingEmbedding(limit: Int = 500) throws -> [EmbeddingBackfillRow] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, topic, title, markdown_path FROM report
                WHERE embedding IS NULL
                ORDER BY generated_at DESC
                LIMIT ?
                """, arguments: [limit]).compactMap { row -> EmbeddingBackfillRow? in
                    guard let idString: String = row["id"],
                          let id = UUID(uuidString: idString),
                          let topic: String = row["topic"],
                          let path: String = row["markdown_path"]
                    else { return nil }
                    let title: String? = row["title"]
                    return EmbeddingBackfillRow(id: id, topic: topic, title: title, markdownPath: path)
                }
        }
    }

    // MARK: - Big story (v15)

    /// Overwrite the (score, headline) pair on a report. Used by the
    /// pipeline at save time and by the launch-time backfill for legacy
    /// rows that pre-dated the v15 migration.
    func saveBigStory(reportID: UUID, score: Double, headline: String?) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE report SET big_story_score = ?, big_story_headline = ? WHERE id = ?",
                arguments: [score, headline, reportID.uuidString]
            )
        }
    }

    /// All scored big-story values for a given preset (or all reports when
    /// presetID is nil). Used to compute a per-preset percentile threshold
    /// so a "big story" badge means "unusually big *for this topic*."
    func bigStoryScores(presetID: UUID?, limit: Int = 50) throws -> [Double] {
        try dbQueue.read { db in
            if let presetID {
                return try Double.fetchAll(db, sql: """
                    SELECT big_story_score FROM report
                    WHERE big_story_score IS NOT NULL AND preset_id = ?
                    ORDER BY generated_at DESC
                    LIMIT ?
                    """, arguments: [presetID.uuidString, limit])
            }
            return try Double.fetchAll(db, sql: """
                SELECT big_story_score FROM report
                WHERE big_story_score IS NOT NULL
                ORDER BY generated_at DESC
                LIMIT ?
                """, arguments: [limit])
        }
    }

    /// Reports missing a `big_story_score`. Used by the launch backfill;
    /// the scorer needs clusters loaded out-of-band so we just return the
    /// report IDs.
    func reportIDsMissingBigStory(limit: Int = 500) throws -> [UUID] {
        try dbQueue.read { db in
            try String.fetchAll(db, sql: """
                SELECT id FROM report
                WHERE big_story_score IS NULL
                ORDER BY generated_at DESC
                LIMIT ?
                """, arguments: [limit]).compactMap(UUID.init(uuidString:))
        }
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
            // last_error is a correlated subquery folded into the main
            // SELECT (no per-row follow-up queries) and scoped to the same
            // time window as the rest of the aggregate so the 30-day view
            // doesn't surface an older error.
            let rows = try Row.fetchAll(db, sql: """
                SELECT source_kind,
                       COUNT(*) AS runs,
                       SUM(CASE WHEN error_message IS NULL THEN 1 ELSE 0 END) AS successes,
                       COALESCE(SUM(items_returned), 0) AS total_returned,
                       COALESCE(SUM(items_fresh), 0) AS total_fresh,
                       AVG(CASE WHEN finished_at IS NOT NULL
                                THEN (julianday(finished_at) - julianday(started_at)) * 86400.0
                                ELSE NULL END) AS avg_latency,
                       MAX(started_at) AS last_run_at,
                       (SELECT error_message FROM source_run sr2
                          WHERE sr2.source_kind = sr.source_kind
                            AND sr2.error_message IS NOT NULL
                            AND sr2.started_at >= ?
                          ORDER BY started_at DESC LIMIT 1) AS last_error
                FROM source_run sr
                WHERE started_at >= ?
                GROUP BY source_kind
                ORDER BY source_kind
                """, arguments: [cutoff, cutoff])
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
                let lastError: String? = row["last_error"]

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
    /// Collapsed by `target_id` (most-recent feedback timestamp per
    /// cluster) so a cluster with multiple feedback kinds doesn't crowd
    /// out other themes.
    func recentDismissedHeadlines(days: Int = 30, limit: Int = 10) throws -> [String] {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        return try dbQueue.read { db in
            try String.fetchAll(db, sql: """
                SELECT c.headline
                FROM cluster c
                JOIN (
                    SELECT target_id, MAX(created_at) AS last_at
                    FROM feedback
                    WHERE target = 'cluster'
                      AND kind IN ('dismiss', 'thumbs_down')
                      AND created_at >= ?
                    GROUP BY target_id
                ) f ON f.target_id = c.id
                ORDER BY f.last_at DESC
                LIMIT ?
                """, arguments: [cutoff, limit])
        }
    }

    // MARK: - Conversation (v9)

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

    // MARK: - Entities (v10)

    /// Upserts an entity by (canonical_name, kind). Returns the row's id —
    /// either the freshly-inserted one or the existing one. Never touches
    /// `mention_count`; that is bumped exclusively by
    /// `recordEntityMention`, which counts only genuinely-new mention
    /// rows, so the counter can't drift on re-runs / backfills.
    @discardableResult
    func upsertEntity(name: String, kind: Entity.Kind, at date: Date = Date()) throws -> UUID {
        try dbQueue.write { db in
            if let existingID: String = try String.fetchOne(db, sql: """
                SELECT id FROM entity
                WHERE canonical_name = ? AND kind = ?
                LIMIT 1
                """, arguments: [name, kind.rawValue]) {
                // Only update last_seen_at here; mention_count is bumped
                // by recordEntityMention when a mention row is actually
                // inserted.
                try db.execute(sql: """
                    UPDATE entity
                    SET last_seen_at = ?
                    WHERE id = ?
                    """, arguments: [date, existingID])
                return UUID(uuidString: existingID) ?? UUID()
            } else {
                let newID = UUID()
                // New entity: mention_count starts at 0; the caller will
                // bump it via recordEntityMention.
                try db.execute(sql: """
                    INSERT INTO entity
                      (id, canonical_name, kind, first_seen_at, last_seen_at, mention_count)
                    VALUES (?, ?, ?, ?, ?, 0)
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
    /// no-ops when the extractor runs twice. `mention_count` is bumped
    /// only when the INSERT actually affected a row (checked via
    /// `changes()` inside the same write transaction), so the counter
    /// can't drift above the real mention count.
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
            // SQLite's `changes()` returns 1 when the INSERT actually
            // wrote a row, 0 when OR IGNORE skipped it.
            if let inserted: Int = try Int.fetchOne(db, sql: "SELECT changes()"),
               inserted > 0 {
                try db.execute(sql: """
                    UPDATE entity SET mention_count = mention_count + 1
                    WHERE id = ?
                    """, arguments: [entityID.uuidString])
            }
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

    // MARK: - Source reliability

    /// Per-host reliability rows. Joins items → report_item → cluster →
    /// feedback to count thumbs-up / thumbs-down / hallucinations against
    /// the clusters where each host's items appeared.
    func sourceReliability(limit: Int = 50) throws -> [SourceReliability] {
        struct Row: Hashable {
            var mentions = 0
            var thumbsUp = 0
            var thumbsDown = 0
            var hallucinations = 0
        }
        var byHost: [String: Row] = [:]

        // The item→cluster edge is resolved by checking whether the item's
        // canonical URL appears in the cluster's citations_json array —
        // done in Swift rather than SQL both for JSON1 portability and so
        // feedback is credited only to hosts the cluster actually cited
        // (a report-level join would credit every host in the report).
        try dbQueue.read { db in
            // 1. Materialize per-report items.
            let itemRows = try GRDB.Row.fetchAll(db, sql: """
                SELECT ri.report_id AS report_id, i.canonical_url AS url
                FROM item i
                JOIN report_item ri ON ri.item_id = i.id
                """)
            struct ItemRow { let reportID: String; let url: String; let host: String }
            let items: [ItemRow] = itemRows.compactMap { row in
                guard let rid: String = row["report_id"],
                      let urlString: String = row["url"],
                      var host = URL(string: urlString)?.host?.lowercased()
                else { return nil }
                if host.hasPrefix("www.") { host.removeFirst(4) }
                return ItemRow(reportID: rid, url: urlString, host: host)
            }

            // 2. Each item contributes one mention to its host.
            for item in items {
                byHost[item.host, default: Row()].mentions += 1
            }

            // 3. For each cluster, look at its citations_json. For every
            //    citation that resolves to one of our known item URLs,
            //    attribute that cluster to the matching host(s). Pull the
            //    per-cluster feedback once and credit each host the cluster
            //    actually cited.
            let clusterRows = try GRDB.Row.fetchAll(db, sql: """
                SELECT c.id AS cluster_id, c.report_id AS report_id, c.citations_json AS cit
                FROM cluster c
                """)
            // Index canonical-URL strings to host (for the cluster lookup).
            var hostByCanonicalURL: [String: String] = [:]
            for item in items { hostByCanonicalURL[item.url] = item.host }

            for row in clusterRows {
                guard let cid: String = row["cluster_id"],
                      let citationsJSON: String = row["cit"]
                else { continue }
                let urls: [String] = (try? Self.decodeJSON(citationsJSON)) ?? []
                let hosts = Set(urls.compactMap { hostByCanonicalURL[$0] })
                guard !hosts.isEmpty else { continue }

                // Pull this cluster's feedback ONCE.
                let counts = try GRDB.Row.fetchAll(db, sql: """
                    SELECT kind, COUNT(*) AS n FROM feedback
                    WHERE target = 'cluster' AND target_id = ?
                    GROUP BY kind
                    """, arguments: [cid])
                for c in counts {
                    let kind: String = c["kind"] ?? ""
                    let n: Int = c["n"] ?? 0
                    for host in hosts {
                        switch kind {
                        case "thumbs_up":     byHost[host, default: Row()].thumbsUp += n
                        case "thumbs_down":   byHost[host, default: Row()].thumbsDown += n
                        case "hallucination": byHost[host, default: Row()].hallucinations += n
                        default: break
                        }
                    }
                }
            }
        }

        let rows = byHost.map { host, r in
            SourceReliability(
                host: host,
                mentions: r.mentions,
                thumbsUp: r.thumbsUp,
                thumbsDown: r.thumbsDown,
                hallucinations: r.hallucinations,
                score: SourceReliability.formula(
                    mentions: r.mentions,
                    thumbsUp: r.thumbsUp,
                    thumbsDown: r.thumbsDown,
                    hallucinations: r.hallucinations
                )
            )
        }
        return Array(rows.sorted { $0.mentions > $1.mentions }.prefix(limit))
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
    /// so a network failure doesn't permanently blacklist items. The lookup
    /// is batched into a single `IN (...)` query.
    func filterUnseen(_ items: [RawItem], presetID: UUID?) throws -> [RawItem] {
        guard !items.isEmpty else { return [] }
        let presetKey = presetID?.uuidString
        return try dbQueue.read { db in
            let hashes = items.map(\.urlHash)
            let placeholders = Array(repeating: "?", count: hashes.count).joined(separator: ",")
            var args: [(any DatabaseValueConvertible)?] = [presetKey]
            args.append(contentsOf: hashes.map { $0 as (any DatabaseValueConvertible)? })
            let seen: Set<String> = try Set(String.fetchAll(db,
                sql: "SELECT url_hash FROM seen_item WHERE preset_id IS ? AND url_hash IN (\(placeholders))",
                arguments: StatementArguments(args)))
            return items.filter { !seen.contains($0.urlHash) }
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
        let title: String? = row["title"]
        let bigStoryScore: Double? = row["big_story_score"]
        let bigStoryHeadline: String? = row["big_story_headline"]
        let sentiment: Double? = row["sentiment"]
        let sentimentRationale: String? = row["sentiment_rationale"]

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
            kind: kind,
            title: title,
            bigStoryScore: bigStoryScore,
            bigStoryHeadline: bigStoryHeadline,
            sentiment: sentiment,
            sentimentRationale: sentimentRationale
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
