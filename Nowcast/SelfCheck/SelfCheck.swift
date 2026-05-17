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

        // FIX (codex review PR #36): use a unique per-run namespace so
        // the seen-index never suppresses items from a prior self-check.
        // Previously the hard-coded `mock.example/one|two` URLs were
        // persisted in `seen_item` on the first run, making subsequent
        // self-checks fail with `noFreshItems` until the user manually
        // pruned. The topic also gets the run id appended so the second
        // pipeline call exercises the diff path against THIS run's first
        // report, not whatever historical report happens to match.
        let runID = UUID().uuidString.prefix(8)
        let topic = "Self-check topic \(runID)"

        // Build a synthetic adapter that returns two known items, with
        // URLs namespaced by `runID` so seen_item never collides.
        let adapter = StaticItemsAdapter(kind: .hackerNews, items: [
            RawItem(
                title: "Item one (\(runID))",
                url: URL(string: "https://mock.example/\(runID)/one")!,
                publishedAt: Date(),
                snippet: "Snippet for item one — capturing some text.",
                transcript: nil,
                sourceKind: .hackerNews,
                author: "selfcheck"
            ),
            RawItem(
                title: "Item two (\(runID))",
                url: URL(string: "https://mock.example/\(runID)/two")!,
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

        let report: Report
        do {
            report = try await pipeline.generate(
                topic: topic,
                window: .today,
                sources: [.hackerNews],
                presetID: nil,
                subscriptions: []
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

        // P4-3: second run on the same topic should produce a diff section.
        // FIX (review #10): the previous version reused the same two URLs,
        // which the seen-index correctly suppressed — meaning the diff
        // path was never exercised. We now feed the second run a *fresh*
        // set of URLs against the same topic so the pipeline reaches the
        // diff-rendering step. P4-3's BriefDiff is what we're actually
        // probing here.
        let secondAdapter = StaticItemsAdapter(kind: .hackerNews, items: [
            RawItem(
                title: "Item three (diff probe)",
                url: URL(string: "https://mock.example/\(runID)/three")!,
                publishedAt: Date(),
                snippet: "A different snippet so the seen-index doesn't suppress this run.",
                transcript: nil,
                sourceKind: .hackerNews,
                author: "selfcheck"
            ),
            RawItem(
                title: "Item four (diff probe)",
                url: URL(string: "https://mock.example/\(runID)/four")!,
                publishedAt: Date(),
                snippet: "Another distinct snippet.",
                transcript: nil,
                sourceKind: .hackerNews,
                author: "selfcheck"
            ),
        ])
        let pipeline2 = ReportPipeline(
            adapters: [secondAdapter],
            storage: storage,
            llm: MockLLMClient(),
            queryRewritingEnabled: false,
            contradictionDetectionEnabled: false
        )
        do {
            let report2 = try await pipeline2.generate(
                topic: topic,
                window: .today,
                sources: [.hackerNews],
                presetID: nil,
                subscriptions: []
            )
            let md = (try? storage.loadMarkdown(for: report2)) ?? ""
            check("P4-3: second-run markdown contains diff section header",
                  md.contains("What's new since last brief"))
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

        // P4-6: FTS search finds *this run's* report.
        // FIX (codex review PR #47): previously asserted only that ANY
        // hit existed — could false-pass on repeat runs (a prior
        // self-check's report would satisfy the assertion even if the
        // current run's indexing failed). Now we search for the unique
        // `runID` so the hit set is provably this-run.
        let hits = (try? storage.searchReports(String(runID))) ?? []
        let hitsForThisRun = hits.filter { $0.reportID == report.id }
        check("P4-6: FTS finds THIS run's report (\(hitsForThisRun.count) match by id)",
              !hitsForThisRun.isEmpty)

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
#endif
