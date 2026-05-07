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

        return m
    }
}
