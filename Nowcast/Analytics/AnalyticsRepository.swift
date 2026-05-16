import Foundation
import GRDB

/// Read-only aggregations over the report/item/source_run tables. The
/// AnalyticsView consumes these directly — no caching layer; queries are
/// cheap and the dataset is bounded by retention.
struct AnalyticsRepository {
    let storage: StorageManager

    struct CostPoint: Identifiable, Hashable {
        var id: Date { day }
        let day: Date
        let usd: Double
    }

    struct TopicPoint: Identifiable, Hashable {
        var id: String { topic }
        let topic: String
        let count: Int
    }

    struct SourceContributionPoint: Identifiable, Hashable {
        var id: SourceKind { sourceKind }
        let sourceKind: SourceKind
        let returned: Int
        let fresh: Int
    }

    struct FunnelStage: Identifiable, Hashable {
        var id: String { stage }
        let stage: String
        let value: Int
    }

    // MARK: - Queries

    func costByDay(lastDays days: Int = 30) throws -> [CostPoint] {
        try storage.dbQueue.read { db in
            let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
            let rows = try Row.fetchAll(db, sql: """
                SELECT date(generated_at) AS day, COALESCE(SUM(usd_cost), 0) AS usd
                FROM report
                WHERE generated_at >= ?
                GROUP BY day
                ORDER BY day ASC
                """, arguments: [cutoff])
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withFullDate, .withDashSeparatorInDate]
            return rows.compactMap { row -> CostPoint? in
                guard let dayStr: String = row["day"] else { return nil }
                let usd: Double = row["usd"] ?? 0
                let date = fmt.date(from: dayStr)
                    ?? Self.fallbackDayParser.date(from: dayStr)
                guard let date else { return nil }
                return CostPoint(day: date, usd: usd)
            }
        }
    }

    func topicFrequency(lastDays days: Int = 30, limit: Int = 10) throws -> [TopicPoint] {
        try storage.dbQueue.read { db in
            let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
            let rows = try Row.fetchAll(db, sql: """
                SELECT topic, COUNT(*) AS c
                FROM report
                WHERE generated_at >= ?
                GROUP BY topic
                ORDER BY c DESC
                LIMIT ?
                """, arguments: [cutoff, limit])
            return rows.compactMap { row -> TopicPoint? in
                guard let topic: String = row["topic"], let c: Int = row["c"] else { return nil }
                return TopicPoint(topic: topic, count: c)
            }
        }
    }

    func sourceContribution(lastDays days: Int = 30) throws -> [SourceContributionPoint] {
        try storage.dbQueue.read { db in
            let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
            let rows = try Row.fetchAll(db, sql: """
                SELECT source_kind,
                       COALESCE(SUM(items_returned), 0) AS r,
                       COALESCE(SUM(items_fresh), 0)    AS f
                FROM source_run
                WHERE started_at >= ?
                GROUP BY source_kind
                ORDER BY r DESC
                """, arguments: [cutoff])
            return rows.compactMap { row -> SourceContributionPoint? in
                guard let kindRaw: String = row["source_kind"],
                      let kind = SourceKind(rawValue: kindRaw)
                else { return nil }
                let r: Int = row["r"] ?? 0
                let f: Int = row["f"] ?? 0
                return SourceContributionPoint(sourceKind: kind, returned: r, fresh: f)
            }
        }
    }

    func freshnessFunnel(lastDays days: Int = 30) throws -> [FunnelStage] {
        try storage.dbQueue.read { db in
            let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
            let returned = try Int.fetchOne(db, sql: """
                SELECT COALESCE(SUM(items_returned), 0) FROM source_run WHERE started_at >= ?
                """, arguments: [cutoff]) ?? 0
            let fresh = try Int.fetchOne(db, sql: """
                SELECT COALESCE(SUM(items_fresh), 0) FROM source_run WHERE started_at >= ?
                """, arguments: [cutoff]) ?? 0
            let linkedFresh = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM report_item ri
                JOIN report r ON r.id = ri.report_id
                WHERE ri.is_fresh = 1 AND r.generated_at >= ?
                """, arguments: [cutoff]) ?? 0
            return [
                FunnelStage(stage: "Returned", value: returned),
                FunnelStage(stage: "Fresh", value: fresh),
                FunnelStage(stage: "In report", value: linkedFresh),
            ]
        }
    }

    private static let fallbackDayParser: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
