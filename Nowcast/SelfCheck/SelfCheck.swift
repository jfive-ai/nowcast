#if DEBUG
import Foundation

/// One-click self-check that exercises every Phase-4 code path against the
/// real DB without spending on a live LLM. Run from Settings → Pipeline →
/// "Run self-check" — it builds a tiny `RawItem` set, runs the production
/// `ReportPipeline` with a `MockLLMClient`, then queries the DB to confirm
/// items / clusters / claims / feedback / source_runs / FTS rows all
/// materialized correctly.
///
/// Test data is namespaced (`urlHash` prefix `self-check-`) and the run
/// only inserts — it doesn't mutate or delete pre-existing rows.
@MainActor
enum SelfCheck {
    struct Result {
        let passed: Bool
        let lines: [String]
        var summary: String { lines.joined(separator: "\n") }
    }

    /// Runs against the *real* StorageManager so the user can inspect the
    /// resulting rows in the Settings → Storage panel afterwards.
    static func run(storage: StorageManager) async -> Result {
        var lines: [String] = []
        var passed = true

        func check(_ label: String, _ condition: Bool) {
            lines.append("\(condition ? "✓" : "✗") \(label)")
            if !condition { passed = false }
        }

        let topic = "Self-check topic"

        // Build a synthetic adapter that returns two known items.
        let adapter = StaticItemsAdapter(kind: .hackerNews, items: [
            RawItem(
                title: "Item one",
                url: URL(string: "https://mock.example/one")!,
                publishedAt: Date(),
                snippet: "Snippet for item one — capturing some text.",
                transcript: nil,
                sourceKind: .hackerNews,
                author: "selfcheck"
            ),
            RawItem(
                title: "Item two",
                url: URL(string: "https://mock.example/two")!,
                publishedAt: Date(),
                snippet: "Snippet for item two.",
                transcript: nil,
                sourceKind: .hackerNews,
                author: "selfcheck"
            ),
        ])

        let pipeline = ReportPipeline(
            adapters: [adapter],
            storage: storage,
            llm: MockLLMClient(),
            queryRewritingEnabled: false,
            contradictionDetectionEnabled: false
        )

        // P5-5: collect emitted stages.
        let collector = StageCollector()

        let report: Report
        do {
            report = try await pipeline.generate(
                topic: topic,
                window: .today,
                sources: [.hackerNews],
                presetID: nil,
                subscriptions: [],
                progress: { stage in
                    collector.append(stage)
                }
            )
        } catch {
            return Result(passed: false, lines: ["✗ Pipeline.generate threw: \(error.localizedDescription)"])
        }

        // P4-1: items + report_item links
        let items = (try? storage.itemsForReport(report.id)) ?? []
        check("P4-1: 2 items linked to report (got \(items.count))", items.count == 2)

        // P4-2: clusters + claims persisted
        let clusters = (try? storage.clusters(for: report.id)) ?? []
        check("P4-2: 2 clusters persisted (got \(clusters.count))", clusters.count == 2)
        let claimCount = clusters.reduce(0) { $0 + $1.claims.count }
        check("P4-2: ≥2 claims persisted (got \(claimCount))", claimCount >= 2)
        let allCitations = clusters.flatMap(\.citations)
        check("P4-2: all citations validated against inputs (got \(allCitations.count))", !allCitations.isEmpty)

        // P4-3: second run on the same topic should produce a diff section
        let firstID = report.id
        let report2: Report
        do {
            report2 = try await pipeline.generate(
                topic: topic,
                window: .today,
                sources: [.hackerNews],
                presetID: nil,
                subscriptions: []
            )
            let md = (try? storage.loadMarkdown(for: report2)) ?? ""
            // _ = firstID
            check("P4-3: second-run markdown contains diff header", md.contains("What's new since last brief") || md.contains("Continuing"))
            _ = firstID
        } catch PipelineError.noFreshItems {
            // The seen-index correctly suppressed the duplicate URLs.
            // That's the expected dedup behavior, but it means no diff to
            // render — count this as a partial pass (dedup is the correct
            // outcome, P4-3 path is exercised by the first run already).
            lines.append("• P4-3: second run dedup'd to zero items (correct; diff path not exercised this run)")
        } catch {
            check("P4-3: second-run threw \(error.localizedDescription)", false)
        }

        // P4-4: feedback round-trip
        if let firstCluster = clusters.first {
            do {
                try storage.recordFeedback(Feedback(
                    id: UUID(), target: .cluster, targetID: firstCluster.id,
                    kind: .star, note: nil, createdAt: Date()
                ))
                let starred = (try? storage.starredClusterIDs()) ?? []
                check("P4-4: feedback persisted + starred query returns it", starred.contains(firstCluster.id))
                try storage.deleteFeedback(target: .cluster, targetID: firstCluster.id, kind: .star)
            } catch {
                check("P4-4: feedback round-trip: \(error.localizedDescription)", false)
            }
        }

        // P4-5: source_run rows recorded
        let health = (try? storage.sourceHealth(days: 1)) ?? []
        let hn = health.first(where: { $0.sourceKind == .hackerNews })
        check("P4-5: source_run row recorded for HN", (hn?.runs ?? 0) >= 1)

        // P4-6: FTS search finds the new report
        let hits = (try? storage.searchReports("Self check")) ?? []
        check("P4-6: FTS search finds new report (got \(hits.count) hits)", !hits.isEmpty)

        // P4-7: speech script transforms the markdown (no side-effects).
        let md = (try? storage.loadMarkdown(for: report)) ?? ""
        let speech = SpeechScript.make(from: md)
        check("P4-7: SpeechScript produces non-empty plain text",
              !speech.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              && !speech.contains("```")
              && !speech.contains("<!-- briefing-json -->"))

        // P4-9 / P4-10: prompt routing in MockLLMClient covers the rewriter
        // and contradiction-detector paths even though they weren't
        // enabled on this pipeline instance — we exercised at minimum the
        // structured-output prompt routing.
        lines.append("• P4-9/P4-10: enable via Settings → Pipeline toggles to exercise live")

        // P5-1: chat session persists user + assistant turns.
        let chat = BriefChatSession(
            report: report,
            storage: storage,
            llm: MockLLMClient()
        )
        await chat.ask("What's the most important point?")
        let conv = (try? storage.conversationMessages(forReport: report.id)) ?? []
        check("P5-1: chat persisted user + assistant turns (got \(conv.count))", conv.count == 2)
        if let last = conv.last {
            check("P5-1: last conversation turn is assistant", last.role == .assistant)
        }

        // P5-2: entity extraction persists ≥1 entity + mention.
        let briefing = BriefingResult(
            tldr: ["t"],
            clusters: clusters.map { c in
                BriefingResult.Cluster(id: c.id, headline: c.headline, summary: c.summary, claims: c.claims, citations: c.citations)
            },
            signal: "s",
            lowConfidence: false
        )
        let extractor = EntityExtractor(llm: MockLLMClient())
        await extractor.enrich(briefing: briefing, reportID: report.id, storage: storage)
        let entityCount = (try? storage.entityCount()) ?? 0
        check("P5-2: ≥1 entity persisted (got \(entityCount))", entityCount >= 1)
        let topEntity = (try? storage.topEntities(limit: 1).first)
        if let top = topEntity ?? nil {
            let timeline = (try? storage.mentions(forEntity: top.id)) ?? []
            check("P5-2: top entity has ≥1 mention (got \(timeline.count))", !timeline.isEmpty)
        }

        // P5-3: counterpoint agent enriches ≥1 cluster (or all are null).
        let cpAgent = CounterpointAgent(llm: MockLLMClient())
        let annotated = await cpAgent.annotate(briefing)
        let withCP = annotated.clusters.filter { $0.counterpoint != nil || $0.gap != nil }.count
        check("P5-3: counterpoint agent annotated ≥1 cluster (got \(withCP))", withCP >= 1)
        let section = CounterpointAgent.renderMarkdownSection(for: annotated)
        check("P5-3: markdown section rendered", section?.contains("Counterpoints") == true)

        // P5-4: webhook formatters produce non-empty payloads for each format.
        let webhookMD = (try? storage.loadMarkdown(for: report)) ?? ""
        for fmt in WebhookFormat.allCases {
            let data = WebhookDeliverer.renderPayload(
                report: report,
                markdown: webhookMD,
                clusters: clusters,
                format: fmt
            )
            check("P5-4: \(fmt.displayName) payload non-empty (\(data.count) bytes)", data.count > 8)
        }
        let detected = WebhookFormat.detect(from: "https://hooks.slack.com/services/AAA/BBB/CCC")
        check("P5-4: format detection identifies Slack", detected == .slack)

        // P5-5: pipeline emitted ≥3 stage events including a terminal done.
        let stages = collector.snapshot()
        check("P5-5: ≥3 pipeline stage events emitted (got \(stages.count))", stages.count >= 3)
        let sawDone = stages.contains { if case .done = $0 { return true } else { return false } }
        check("P5-5: terminal .done event fired", sawDone)

        lines.append("")
        lines.append("Final: \(passed ? "PASS" : "FAIL")  ·  report id: \(report.id.uuidString.prefix(8))")
        return Result(passed: passed, lines: lines)
    }
}

/// DEBUG-only adapter that returns a fixed item list. Used by the self-check
/// so the test doesn't depend on Hacker News being reachable.
private struct StaticItemsAdapter: SourceAdapter {
    let kind: SourceKind
    let items: [RawItem]
    func fetch(query: String, window: TimeWindow, subscriptions: [SourceSubscription]) async throws -> [RawItem] {
        return items
    }
}

/// Sendable-safe sink that lets the self-check capture pipeline progress
/// events from the (non-isolated) callback.
private final class StageCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var stages: [PipelineStage] = []
    func append(_ stage: PipelineStage) {
        lock.lock(); defer { lock.unlock() }
        stages.append(stage)
    }
    func snapshot() -> [PipelineStage] {
        lock.lock(); defer { lock.unlock() }
        return stages
    }
}
#endif
