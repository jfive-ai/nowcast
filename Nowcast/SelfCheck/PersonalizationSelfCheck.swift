#if DEBUG
import Foundation
import GRDB

@MainActor
enum PersonalizationSelfCheck {
    static func run(storage: StorageManager, check: (String, Bool) -> Void) async {
        let defaults = BriefingPrompt.render(topic: "Rust", window: .today, items: [])
        check("P7-3: default prompt omits Style and editorial opinions",
              !defaults.contains("# Style") && !defaults.contains("opinionated"))
        for depth in BriefDepth.allCases {
            for tone in BriefTone.allCases where depth != .standard || tone != .neutral {
                let prompt = BriefingPrompt.render(topic: "Rust", window: .today, items: [], depth: depth, tone: tone)
                check("P7-3: \(depth.rawValue)/\(tone.rawValue) style preserves citations and footer",
                      prompt.contains("# Style") && prompt.contains(depth.instruction)
                      && prompt.contains(tone.instruction) && prompt.contains("<!-- briefing-json -->")
                      && prompt.contains("Every URL in `citations` MUST appear in the inputs above"))
            }
        }
        do {
            let db = try DatabaseQueue()
            try Schema.migrator().migrate(db, upTo: "v18")
            try await db.write { db in
                try db.execute(sql: """
                    INSERT INTO topic_preset (id, name, query, window, sources_json, created_at)
                    VALUES (?, 'Legacy', 'Rust', 'today', '[]', ?)
                    """, arguments: [UUID().uuidString, Date()])
            }
            try Schema.migrator().migrate(db)
            let migratedDefaults: Bool = try await db.read { db in
                guard let row = try Row.fetchOne(db, sql: "SELECT depth, tone FROM topic_preset") else { return false }
                let depth: String = row["depth"]
                let tone: String = row["tone"]
                return depth == "standard" && tone == "neutral"
            }
            check("P7-3: v18 presets migrate to standard/neutral", migratedDefaults)
            try Schema.migrator().migrate(db)
            check("P7-3: v19 migration is repeatable", true)

            var preset = TopicPreset(name: "Style self-check", query: "Rust", sources: [.hackerNews], depth: .deep, tone: .technical)
            defer { try? storage.deletePreset(id: preset.id) }
            try storage.upsertPreset(preset)
            var loaded = try storage.listPresets().first { $0.id == preset.id }
            check("P7-3: non-default style persists", loaded?.depth == .deep && loaded?.tone == .technical)
            preset.depth = .skim
            preset.tone = .opinionated
            try storage.upsertPreset(preset)
            loaded = try storage.listPresets().first { $0.id == preset.id }
            check("P7-3: edited style persists", loaded?.depth == .skim && loaded?.tone == .opinionated)

            let encoded = try JSONEncoder().encode(preset)
            let decoded = try JSONDecoder().decode(TopicPreset.self, from: encoded)
            check("P7-3: style survives Codable round-trip", decoded == preset)
            var legacy = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] ?? [:]
            legacy.removeValue(forKey: "depth")
            legacy.removeValue(forKey: "tone")
            let legacyData = try JSONSerialization.data(withJSONObject: legacy)
            let legacyPreset = try JSONDecoder().decode(TopicPreset.self, from: legacyData)
            check("P7-3: old preset JSON defaults style", legacyPreset.depth == .standard && legacyPreset.tone == .neutral)

            let llm = PromptRecorder()
            let adapter = StyleAdapter()
            let pipeline = ReportPipeline(adapters: [adapter], storage: storage, llm: llm)
            let report = try await pipeline.generate(topic: preset.query, window: preset.window, sources: preset.sources,
                                                     presetID: preset.id, depth: preset.depth, tone: preset.tone)
            check("P7-3: production pipeline passes style without extra LLM calls",
                  llm.prompts.count == 1 && llm.prompts[0].contains("Depth: Skim") && llm.prompts[0].contains("Tone: Opinionated"))
            _ = try storage.deleteReports(ids: [report.id])
        } catch {
            check("P7-3: storage / pipeline (\(error))", false)
        }
    }

    private final class PromptRecorder: LLMClient {
        let providerName = "mock"
        let defaultModel = "mock"
        var prompts: [String] = []
        func summarize(prompt: String, model: String?) async throws -> LLMResponse {
            prompts.append(prompt)
            return try await MockLLMClient().summarize(prompt: prompt, model: model)
        }
    }

    private struct StyleAdapter: SourceAdapter {
        let kind = SourceKind.hackerNews
        func fetch(query: String, window: TimeWindow, subscriptions: [SourceSubscription]) async throws -> [RawItem] {
            [RawItem(title: "Rust runtime update", url: URL(string: "https://mock.example/style/\(UUID())")!,
                     publishedAt: Date(), snippet: "Runtime scheduling changes", transcript: nil,
                     sourceKind: kind, author: nil)]
        }
    }
}
#endif
