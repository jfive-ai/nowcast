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

        // v5: persist the machine-readable clusters + claims the LLM emits
        // alongside its markdown (P4-2). Unblocks diff (P4-3), feedback
        // targets (P4-4), and contradiction detection (P4-10).
        m.registerMigration("v5") { db in
            try db.create(table: "cluster") { t in
                t.column("id", .text).primaryKey()
                t.column("report_id", .text)
                    .notNull()
                    .references("report", onDelete: .cascade)
                t.column("headline", .text).notNull()
                t.column("summary", .text).notNull()
                t.column("ord", .integer).notNull()
                t.column("citations_json", .text).notNull().defaults(to: "[]")
            }
            try db.create(indexOn: "cluster", columns: ["report_id"])

            try db.create(table: "claim") { t in
                t.column("id", .text).primaryKey()
                t.column("cluster_id", .text)
                    .notNull()
                    .references("cluster", onDelete: .cascade)
                t.column("text", .text).notNull()
                t.column("citations_json", .text).notNull().defaults(to: "[]")
                t.column("ord", .integer).notNull()
            }
            try db.create(indexOn: "claim", columns: ["cluster_id"])
        }

        // v6: per-target feedback rows (P4-4). `target` discriminates
        // between report-level and cluster-level feedback; `target_id`
        // refers to `report.id` or `cluster.id` accordingly.
        m.registerMigration("v6") { db in
            try db.create(table: "feedback") { t in
                t.column("id", .text).primaryKey()
                t.column("target", .text).notNull()
                t.column("target_id", .text).notNull()
                t.column("kind", .text).notNull()
                t.column("note", .text)
                t.column("created_at", .datetime).notNull().indexed()
            }
            try db.create(indexOn: "feedback", columns: ["target", "target_id"])
        }

        // v7: per-adapter outcomes per run (P4-5 source health & trust).
        // One row per (report, source_kind) — captures latency, fetch
        // success, items returned, and error text when present.
        m.registerMigration("v7") { db in
            try db.create(table: "source_run") { t in
                t.column("id", .text).primaryKey()
                t.column("report_id", .text)
                    .notNull()
                    .references("report", onDelete: .cascade)
                t.column("source_kind", .text).notNull()
                t.column("started_at", .datetime).notNull()
                t.column("finished_at", .datetime)
                t.column("items_returned", .integer).notNull().defaults(to: 0)
                t.column("items_fresh", .integer).notNull().defaults(to: 0)
                t.column("error_message", .text)
            }
            try db.create(indexOn: "source_run",
                          columns: ["source_kind", "started_at"])
        }

        // v8: full-text search over report topic+markdown and per-item
        // title+snippet (P4-6). FTS5 with porter stemming + an "external
        // content" virtual table would be nicest but GRDB's FTS helpers
        // are a thin wrapper — we keep it simple and maintain the index
        // ourselves on every report insert (in StorageManager).
        m.registerMigration("v8") { db in
            try db.execute(sql: """
                CREATE VIRTUAL TABLE report_fts USING fts5(
                    report_id UNINDEXED,
                    topic,
                    body,
                    tokenize = 'porter'
                );
                """)
            try db.execute(sql: """
                CREATE VIRTUAL TABLE item_fts USING fts5(
                    item_id UNINDEXED,
                    title,
                    snippet,
                    tokenize = 'porter'
                );
                """)
        }

        // v9: per-report conversation thread (P5-1). One row per turn,
        // ordered by created_at. Cascade-delete with the parent report.
        m.registerMigration("v9") { db in
            try db.create(table: "conversation_message") { t in
                t.column("id", .text).primaryKey()
                t.column("report_id", .text)
                    .notNull()
                    .references("report", onDelete: .cascade)
                t.column("role", .text).notNull()
                t.column("text", .text).notNull()
                t.column("citations_json", .text).notNull().defaults(to: "[]")
                t.column("created_at", .datetime).notNull()
            }
            try db.create(indexOn: "conversation_message",
                          columns: ["report_id", "created_at"])
        }

        // v10: cross-brief entity index (P5-2). One row per canonical
        // (name, kind); mention rows fan out to (entity, report, cluster).
        m.registerMigration("v10") { db in
            try db.create(table: "entity") { t in
                t.column("id", .text).primaryKey()
                t.column("canonical_name", .text).notNull()
                t.column("kind", .text).notNull()
                t.column("first_seen_at", .datetime).notNull()
                t.column("last_seen_at", .datetime).notNull()
                t.column("mention_count", .integer).notNull().defaults(to: 0)
                t.uniqueKey(["canonical_name", "kind"])
            }
            try db.create(indexOn: "entity", columns: ["mention_count"])

            try db.create(table: "entity_mention") { t in
                t.column("entity_id", .text)
                    .notNull()
                    .references("entity", onDelete: .cascade)
                t.column("report_id", .text)
                    .notNull()
                    .references("report", onDelete: .cascade)
                t.column("cluster_id", .text)
                t.primaryKey(["entity_id", "report_id", "cluster_id"])
            }
            try db.create(indexOn: "entity_mention", columns: ["entity_id"])
            try db.create(indexOn: "entity_mention", columns: ["report_id"])
        }

        // v11: per-cluster steel-man counterpoint + "what's not covered"
        // gap (P5-3). Both columns are nullable; old clusters stay valid.
        m.registerMigration("v11") { db in
            try db.alter(table: "cluster") { t in
                t.add(column: "counterpoint", .text)
                t.add(column: "gap", .text)
            }
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
