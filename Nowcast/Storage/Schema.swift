import Foundation
import GRDB

/// Database schema migrations. Bump by adding a new migration; never edit
/// existing migrations after they ship.
enum Schema {
    static func migrator() -> DatabaseMigrator {
        var m = DatabaseMigrator()

        m.registerMigration("v1") { db in
            try db.create(table: "topic_preset") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("query", .text).notNull()
                t.column("sources_json", .text).notNull()
                t.column("created_at", .datetime).notNull()
                t.column("last_run_at", .datetime)
            }

            try db.create(table: "report") { t in
                t.column("id", .text).primaryKey()
                t.column("preset_id", .text)
                    .references("topic_preset", onDelete: .setNull)
                t.column("topic", .text).notNull()
                t.column("window", .text).notNull()
                t.column("generated_at", .datetime).notNull().indexed()
                t.column("markdown_path", .text).notNull()
                t.column("byte_size", .integer).notNull()
                t.column("source_count", .integer).notNull()
            }

            try db.create(table: "source_subscription") { t in
                t.column("id", .text).primaryKey()
                t.column("kind", .text).notNull()
                t.column("identifier", .text).notNull()
                t.column("label", .text).notNull()
            }

            try db.create(table: "seen_item") { t in
                t.autoIncrementedPrimaryKey("rowid")
                t.column("preset_id", .text)
                t.column("url_hash", .text).notNull().indexed()
                t.column("first_seen_at", .datetime).notNull()
                t.uniqueKey(["preset_id", "url_hash"])
            }
        }

        // v2: presets gain cadence + delivery + window;
        //     reports gain a read_at marker for the menu-bar unread badge.
        m.registerMigration("v2") { db in
            try db.alter(table: "topic_preset") { t in
                t.add(column: "window", .text).notNull().defaults(to: TimeWindow.today.rawValue)
                t.add(column: "cadence_json", .text).notNull().defaults(to: Self.manualCadenceJSON)
                t.add(column: "delivery_json", .text).notNull().defaults(to: Self.defaultDeliveryJSON)
            }
            try db.alter(table: "report") { t in
                t.add(column: "read_at", .datetime)
            }
        }

        // v3: reports gain LLM usage + cost columns. All nullable so
        // existing rows survive untouched.
        m.registerMigration("v3") { db in
            try db.alter(table: "report") { t in
                t.add(column: "prompt_tokens", .integer)
                t.add(column: "completion_tokens", .integer)
                t.add(column: "usd_cost", .double)
                t.add(column: "model_used", .text)
                t.add(column: "provider_used", .text)
            }
        }

        // v4: per-item persistence. Every RawItem that survives in-run dedup
        // is upserted into `item`, then linked to its parent report via
        // `report_item`. Foundation for diff, timeline, source-trust, and
        // analytics features (see issue #15 / P4-1).
        m.registerMigration("v4") { db in
            try db.create(table: "item") { t in
                t.column("id", .text).primaryKey()
                t.column("canonical_url", .text).notNull()
                t.column("url_hash", .text).notNull().indexed()
                t.column("title", .text).notNull()
                t.column("snippet", .text)
                t.column("transcript", .text)
                t.column("source_kind", .text).notNull()
                t.column("author", .text)
                t.column("published_at", .datetime)
                t.column("first_seen_at", .datetime).notNull()
                t.uniqueKey(["url_hash"])
            }
            try db.create(indexOn: "item", columns: ["published_at"])

            try db.create(table: "report_item") { t in
                t.column("report_id", .text)
                    .notNull()
                    .references("report", onDelete: .cascade)
                t.column("item_id", .text)
                    .notNull()
                    .references("item", onDelete: .cascade)
                t.column("is_fresh", .integer).notNull().defaults(to: 1)
                t.primaryKey(["report_id", "item_id"])
            }
            try db.create(indexOn: "report_item", columns: ["item_id"])
        }

        return m
    }

    /// `Cadence.manual` encoded as JSON. Used as the default for rows
    /// that pre-existed before the v2 migration.
    private static let manualCadenceJSON: String = {
        let data = (try? JSONEncoder().encode(Cadence.manual)) ?? Data("{}".utf8)
        return String(data: data, encoding: .utf8) ?? "{}"
    }()

    /// `[.inApp]` encoded as JSON.
    private static let defaultDeliveryJSON: String = {
        let data = (try? JSONEncoder().encode([DeliveryChannel.inApp])) ?? Data("[]".utf8)
        return String(data: data, encoding: .utf8) ?? "[]"
    }()
}
