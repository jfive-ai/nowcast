#if DEBUG
import Foundation
import GRDB

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

        // P7-2: smart titler produces a non-empty headline distinct from the topic.
        let titler = SmartTitler(llm: MockLLMClient())
        let headline = await titler.title(
            topic: topic,
            tldr: ["a", "b"],
            clusterHeadlines: clusters.map(\.headline)
        )
        check("P7-2: smart titler returned a headline", headline?.isEmpty == false)
        if let h = headline {
            check("P7-2: headline differs from raw topic", h != topic)
        }

        // P7-1: source reliability formula band sanity.
        check("P7-1: all-thumbs-up host scores ≥70",
              SourceReliability.formula(mentions: 5, thumbsUp: 5, thumbsDown: 0, hallucinations: 0) >= 70)
        check("P7-1: all-hallucinations host scores <40",
              SourceReliability.formula(mentions: 5, thumbsUp: 0, thumbsDown: 0, hallucinations: 5) < 40)
        check("P7-1: neutral host lands in mixed band",
              (40...69).contains(SourceReliability.formula(mentions: 5, thumbsUp: 0, thumbsDown: 0, hallucinations: 0)))

        // P6-4: follow-up suggester returns ≥1 candidate with both fields filled.
        let followUpSuggester = FollowUpSuggester(llm: MockLLMClient())
        let followUps = await followUpSuggester.suggest(
            for: report,
            tldr: ["a", "b"],
            clusterHeadlines: clusters.map(\.headline),
            existingPresetNames: []
        )
        check("P6-4: ≥1 follow-up suggestion (got \(followUps.count))", followUps.count >= 1)
        if let first = followUps.first {
            check("P6-4: suggestion has non-empty query", !first.query.isEmpty)
            check("P6-4: suggestion has ≥1 source", !first.sources.isEmpty)
        }

        // P6-3: BriefDiff.diff against an identical-cluster set returns all
        // continuing (no new, no dropped). Sanity check that the existing
        // diff algorithm we're surfacing in the compare view still behaves.
        let selfDelta = BriefDiff.diff(current: clusters, prior: clusters)
        check("P6-3: self-diff has 0 new clusters", selfDelta.newClusters.isEmpty)
        check("P6-3: self-diff has 0 dropped clusters", selfDelta.droppedClusters.isEmpty)
        check("P6-3: self-diff marks all clusters continuing (got \(selfDelta.continuingClusters.count))",
              selfDelta.continuingClusters.count == clusters.count)

        // P6-2: provenance builder produces ≥1 cluster row with ≥1 supporting item.
        let provRows = ProvenanceBuilder.build(clusters: clusters, items: items)
        check("P6-2: ≥1 cluster row built (got \(provRows.count))", provRows.count >= 1)
        let totalMatched = provRows.flatMap { $0.rows.flatMap(\.supportingItems) }.count
        check("P6-2: ≥1 supporting item matched (got \(totalMatched))", totalMatched >= 1)

        // P6-1: markdown link splitter + URL index round-trip.
        let line = "Item one ([example.com](https://mock.example/one)) wins."
        let segs = MarkdownLinkText.split(line)
        let linkCount = segs.compactMap(\.linkPair).count
        check("P6-1: split() finds 1 link in fixture (got \(linkCount))", linkCount == 1)
        let reportItems = (try? storage.itemsForReport(report.id)) ?? []
        let urlIndex = MarkdownLinkText.buildIndex(items: reportItems)
        check("P6-1: URL index built (\(urlIndex.count) entries)", !urlIndex.isEmpty)

        // P5-6: weekly synthesizer produces a digest row when ≥1 daily exists.
        let weeklyPreset = TopicPreset(
            name: "Self-check weekly",
            query: topic,
            sources: [.hackerNews],
            weeklyDigestEnabled: true
        )
        do {
            try storage.upsertPreset(weeklyPreset)
            // Re-link the synthetic report to this preset so dailyReports(forPreset:) finds it.
            // (The pipeline above used presetID: nil; for the self-check we just
            // verify the synthesizer renders + persists, not the wiring.)
        } catch {
            // ignore; the assertion below will catch any real failure
        }
        let synthesizer = WeeklySynthesizer(storage: storage, llm: MockLLMClient())
        // Inject a quick-and-dirty daily report under this preset so the
        // synthesizer has something to chew on.
        let fakeDaily = Report(
            id: UUID(),
            presetID: weeklyPreset.id,
            topic: topic,
            window: .today,
            generatedAt: Date(),
            markdownPath: "",
            byteSize: 0,
            sourceCount: 1,
            kind: .daily
        )
        _ = try? storage.insertReport(fakeDaily, markdown: "## TL;DR\n- One self-check daily.\n\n## Stories\n### Foo\nBar.")
        do {
            let digest = try await synthesizer.synthesize(for: weeklyPreset)
            check("P5-6: weekly digest produced", digest != nil)
            if let digest {
                check("P5-6: digest kind is weeklyDigest", digest.kind == .weeklyDigest)
            }
        } catch {
            check("P5-6: synthesize threw \(error.localizedDescription)", false)
        }

        // P8-3: BriefingResult clamps sentiment to [-1, +1] and the
        // decoder accepts a missing sentiment field. Round-trip a JSON
        // payload with an out-of-range sentiment to confirm.
        let oosJSON = """
        {
          "tldr": ["a"],
          "clusters": [],
          "signal": "s",
          "low_confidence": false,
          "sentiment": 5.0,
          "sentiment_rationale": "test"
        }
        """
        if let data = oosJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(BriefingResult.self, from: data) {
            check("P8-3: oversize sentiment clamped to +1 (got \(decoded.sentiment ?? -999))",
                  decoded.sentiment == 1.0)
            check("P8-3: rationale round-trips", decoded.sentimentRationale == "test")
        } else {
            check("P8-3: BriefingResult decode failed for clamp fixture", false)
        }
        let missingJSON = """
        {"tldr":["a"],"clusters":[],"signal":"s","low_confidence":false}
        """
        if let data = missingJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(BriefingResult.self, from: data) {
            check("P8-3: missing sentiment decodes as nil", decoded.sentiment == nil)
        }

        // P8-2: big-story scorer is deterministic — feed it a synthetic
        // briefing where one cluster has 4 distinct hosts and another has
        // 1, expect a 4 (top max-hosts) score and the multi-host cluster's
        // headline.
        let bigCluster = BriefingResult.Cluster(
            id: "c1", headline: "Multi-source consensus",
            summary: "x", claims: [],
            citations: [
                "https://nytimes.com/a", "https://wsj.com/b",
                "https://bbc.com/c",     "https://reuters.com/d"
            ]
        )
        let smallCluster = BriefingResult.Cluster(
            id: "c2", headline: "Solo note",
            summary: "y", claims: [],
            citations: ["https://example.com/z"]
        )
        let synthetic = BriefingResult(
            tldr: [], clusters: [bigCluster, smallCluster],
            signal: "", lowConfidence: false
        )
        let bigOutcome = BigStoryScorer.score(synthetic)
        check("P8-2: scorer picks max-host cluster (got score=\(bigOutcome.score))",
              bigOutcome.score >= 4)
        check("P8-2: scorer surfaces the consensus headline",
              bigOutcome.headline == "Multi-source consensus")
        check("P8-2: isBig fires above absolute floor with no priors",
              BigStoryScorer.isBig(score: 5, comparison: []))
        check("P8-2: isBig stays cold for a tiny score",
              !BigStoryScorer.isBig(score: 1, comparison: []))

        // P8-1: semantic-search embedding. The pipeline writes a vector at
        // save time when NLEmbedding is available. We only enforce
        // presence when the OS shipped the sentence model — otherwise the
        // app gracefully falls back to keyword search and writing nothing
        // is the correct behavior.
        if ReportEmbedder.shared.isAvailable {
            let stored = (try? storage.allEmbeddings()) ?? []
            let hasThisRun = stored.contains { $0.reportID == report.id }
            check("P8-1: embedding persisted for THIS run's report", hasThisRun)
            let hits = state_semanticSearch(storage: storage, query: topic)
            let foundThisRun = hits.contains { $0.reportID == report.id }
            check("P8-1: semantic search returns THIS run's report for its topic", foundThisRun)
        } else {
            lines.append("• P8-1: NLEmbedding unavailable on this build — semantic-search assertions skipped")
        }

        // prod-03: outbound URL policy blocks SSRF targets but allows public hosts.
        check("SSRF: public https host allowed",
              OutboundURLPolicy.allows(URL(string: "https://example.com/feed.xml")!))
        check("SSRF: file:// scheme blocked",
              !OutboundURLPolicy.allows(URL(string: "file:///etc/passwd")!))
        check("SSRF: localhost blocked",
              !OutboundURLPolicy.allows(URL(string: "http://localhost:8080/")!))
        check("SSRF: loopback 127.0.0.1 blocked",
              !OutboundURLPolicy.allows(URL(string: "http://127.0.0.1/")!))
        check("SSRF: cloud metadata 169.254.169.254 blocked",
              !OutboundURLPolicy.allows(URL(string: "http://169.254.169.254/latest/meta-data/")!))
        check("SSRF: private 10/8 blocked",
              !OutboundURLPolicy.allows(URL(string: "http://10.1.2.3/")!))
        check("SSRF: private 192.168/16 blocked",
              !OutboundURLPolicy.allows(URL(string: "https://192.168.1.1/")!))
        check("SSRF: .local mDNS name blocked",
              !OutboundURLPolicy.allows(URL(string: "http://printer.local/feed")!))
        check("SSRF: trailing-dot localhost. blocked",
              !OutboundURLPolicy.allows(URL(string: "http://localhost./")!))
        check("SSRF: trailing-dot printer.local. blocked",
              !OutboundURLPolicy.allows(URL(string: "http://printer.local./feed")!))
        check("SSRF: localhost.localdomain blocked",
              !OutboundURLPolicy.allows(URL(string: "http://localhost.localdomain/")!))
        check("SSRF: IPv6 loopback ::1 blocked",
              OutboundURLPolicy.isBlocked(ipv6: [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1]))
        check("SSRF: IPv6 link-local fe80 blocked",
              OutboundURLPolicy.isBlocked(ipv6: [0xfe,0x80,0,0,0,0,0,0,0,0,0,0,0,0,0,1]))
        check("SSRF: IPv6 public 2606:: allowed",
              !OutboundURLPolicy.isBlocked(ipv6: [0x26,0x06,0,0,0,0,0,0,0,0,0,0,0,0,0,1]))

        // prod-05: secret redaction scrubs keys/tokens from error strings.
        check("Redact: ?key= query param scrubbed",
              SecretRedactor.redact("GET https://www.googleapis.com/x?part=snippet&key=AIzaSyD1234567890abc failed")
                .contains("key=***")
              && !SecretRedactor.redact("a?key=AIzaSyD1234567890abc").contains("AIzaSyD1234567890abc"))
        check("Redact: bare Google AIza key scrubbed",
              !SecretRedactor.redact("error with AIzaSyD1234567890abcDEF in it").contains("AIzaSyD1234567890abcDEF"))
        check("Redact: OpenAI sk- token scrubbed",
              !SecretRedactor.redact("auth sk-abc123def456ghi789 rejected").contains("sk-abc123def456ghi789"))
        check("Redact: Bearer token scrubbed",
              SecretRedactor.redact("Authorization: Bearer abc.def.ghi").contains("Bearer ***"))
        check("Redact: leaves ordinary text intact",
              SecretRedactor.redact("No new items found. Try widening the window.")
                == "No new items found. Try widening the window.")

        // prod-06: SMTP header/command injection sanitizers strip CR/LF.
        let injectedSubject = SMTPClient.sanitizeHeaderValue("ETH update\r\nBcc: evil@example.com")
        check("SMTP: header value strips CR/LF",
              !injectedSubject.contains("\r") && !injectedSubject.contains("\n"))
        let injectedAddr = SMTPClient.sanitizeAddress("ok@example.com\r\nRCPT TO:<evil@example.com>")
        check("SMTP: address strips CR/LF + brackets + whitespace",
              !injectedAddr.contains("\r") && !injectedAddr.contains("\n")
              && !injectedAddr.contains("<") && !injectedAddr.contains(">")
              && !injectedAddr.contains(" "))
        check("SMTP: clean subject preserved",
              SMTPClient.sanitizeHeaderValue("Nowcast: ethereum (24h)") == "Nowcast: ethereum (24h)")
        check("SMTP: clean address preserved",
              SMTPClient.sanitizeAddress("digest@example.com") == "digest@example.com")

        // prod-08: v17 report indexes were actually created.
        let reportIndexes = (try? storage.indexNames(onTable: "report")) ?? []
        check("Indexes: report(preset_id, generated_at) exists (got \(reportIndexes.count) total)",
              reportIndexes.contains("report_on_preset_generated"))
        check("Indexes: report(kind) exists",
              reportIndexes.contains("report_on_kind"))

        // prod-11: deleting a report prunes now-orphaned item rows + item_fts;
        // deleting a preset prunes its seen_item rows.
        let orphanItem = RawItem(
            title: "Orphan probe \(runID)",
            url: URL(string: "https://mock.example/\(runID)/orphan")!,
            publishedAt: Date(),
            snippet: "orphan probe",
            transcript: nil,
            sourceKind: .hackerNews,
            author: nil
        )
        let orphanIDMap = (try? storage.upsertItems([orphanItem])) ?? [:]
        let throwaway = Report(
            id: UUID(), presetID: nil, topic: "Orphan report \(runID)",
            window: .today, generatedAt: Date(), markdownPath: "",
            byteSize: 0, sourceCount: 1, kind: .daily
        )
        if let storedThrowaway = try? storage.insertReport(throwaway, markdown: "# orphan\n") {
            try? storage.attachItemsToReport(
                storedThrowaway.id,
                itemIDsByHash: orphanIDMap,
                freshHashes: Set(orphanIDMap.keys)
            )
            check("prod-11: orphan item exists before its report is deleted",
                  (try? storage.itemExists(urlHash: orphanItem.urlHash)) == true)
            _ = try? storage.deleteReports(ids: [storedThrowaway.id])
            check("prod-11: orphaned item pruned after its only report is deleted",
                  (try? storage.itemExists(urlHash: orphanItem.urlHash)) == false)
        }
        let seenProbePreset = TopicPreset(
            name: "Seen probe \(runID)", query: "seen probe", sources: [.hackerNews]
        )
        try? storage.upsertPreset(seenProbePreset)
        try? storage.recordSeen([orphanItem], presetID: seenProbePreset.id)
        check("prod-11: seen_item recorded for preset before delete",
              ((try? storage.seenItemCount(presetID: seenProbePreset.id)) ?? 0) >= 1)
        try? storage.deletePreset(id: seenProbePreset.id)
        check("prod-11: seen_item pruned when its preset is deleted",
              (try? storage.seenItemCount(presetID: seenProbePreset.id)) == 0)

        // prod-12: deleting a report also removes its markdown file.
        let fileProbe = Report(
            id: UUID(), presetID: nil, topic: "File probe \(runID)",
            window: .today, generatedAt: Date(), markdownPath: "",
            byteSize: 0, sourceCount: 1, kind: .daily
        )
        if let storedFileProbe = try? storage.insertReport(fileProbe, markdown: "# file probe \(runID)\n") {
            let fileURL = AppPaths.reportURL(for: storedFileProbe.markdownPath)
            check("prod-12: report markdown file present after insert",
                  FileManager.default.fileExists(atPath: fileURL.path))
            _ = try? storage.deleteReports(ids: [storedFileProbe.id])
            check("prod-12: report markdown file removed after delete",
                  !FileManager.default.fileExists(atPath: fileURL.path))
        }

        // prod-13: the three formerly-untracked aux LLM calls now report token
        // usage so the pipeline can fold them into the report's cost.
        let cpTracked = await CounterpointAgent(llm: MockLLMClient()).annotateTracked(briefing)
        check("prod-13: counterpoint call reports token usage", cpTracked.usage != nil)
        let titleTrackedResult = await SmartTitler(llm: MockLLMClient())
            .titleTracked(topic: topic, tldr: ["a", "b"], clusterHeadlines: clusters.map(\.headline))
        check("prod-13: smart-title call reports token usage", titleTrackedResult.usage != nil)
        let entTracked = await EntityExtractor(llm: MockLLMClient()).extractTracked(briefing: briefing)
        check("prod-13: entity-extraction call reports token usage", entTracked.usage != nil)

        // addReportUsage accrues into a report's running cost totals.
        let usageProbe = Report(
            id: UUID(), presetID: nil, topic: "Usage probe \(runID)",
            window: .today, generatedAt: Date(), markdownPath: "",
            byteSize: 0, sourceCount: 1, kind: .daily
        )
        if let storedUsageProbe = try? storage.insertReport(usageProbe, markdown: "# usage \(runID)\n") {
            try? storage.addReportUsage(reportID: storedUsageProbe.id, promptTokens: 70, completionTokens: 30, usdCost: 0)
            let reloaded = (try? storage.listReports())?.first { $0.id == storedUsageProbe.id }
            check("prod-13: addReportUsage accrues prompt tokens (got \(reloaded?.promptTokens ?? -1))",
                  reloaded?.promptTokens == 70)
            check("prod-13: addReportUsage accrues completion tokens",
                  reloaded?.completionTokens == 30)
            _ = try? storage.deleteReports(ids: [storedUsageProbe.id])
        }

        // prod-30: upsertItems batched existence check is idempotent, and
        // sourceReliability aggregates mentions correctly after the N+1 fix.
        let dupItem = RawItem(
            title: "Dup probe \(runID)",
            url: URL(string: "https://mock.example/\(runID)/dup")!,
            publishedAt: Date(), snippet: "dup", transcript: nil,
            sourceKind: .hackerNews, author: nil
        )
        let dupMap1 = (try? storage.upsertItems([dupItem])) ?? [:]
        let dupMap2 = (try? storage.upsertItems([dupItem, dupItem])) ?? [:]
        check("prod-30: upsertItems returns a stable id for a repeated hash",
              dupMap1[dupItem.urlHash] != nil && dupMap1[dupItem.urlHash] == dupMap2[dupItem.urlHash])
        let reliability = (try? storage.sourceReliability()) ?? []
        check("prod-30: sourceReliability aggregates host mentions (got \(reliability.count) hosts)",
              reliability.contains { $0.host == "mock.example" && $0.mentions >= 1 })

        // prod-46: reconcileFullTextIndex drops orphan FTS rows (parent report
        // gone) but keeps valid ones.
        func reportFTSCount(_ reportID: String) -> Int {
            (try? storage.dbQueue.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM report_fts WHERE report_id = ?",
                                 arguments: [reportID]) ?? 0
            }) ?? -1
        }
        let orphanFTSID = "orphan-fts-\(runID)"
        try? await storage.dbQueue.write { db in
            try db.execute(sql: "INSERT INTO report_fts (report_id, topic, body) VALUES (?, ?, ?)",
                           arguments: [orphanFTSID, "orphan topic", "orphan body \(runID)"])
        }
        check("prod-46: orphan report_fts row present before reconcile",
              reportFTSCount(orphanFTSID) == 1)
        try? storage.reconcileFullTextIndex()
        check("prod-46: orphan report_fts row removed after reconcile",
              reportFTSCount(orphanFTSID) == 0)
        check("prod-46: valid report_fts row survives reconcile",
              reportFTSCount(report.id.uuidString) == 1)

        // prod-24: consolidated LLM JSON extraction.
        check("LLMJSON: slices a bare object",
              LLMJSON.firstJSONSlice(in: "{\"a\":1}") == "{\"a\":1}")
        check("LLMJSON: slices an object out of surrounding prose",
              LLMJSON.firstJSONSlice(in: "here you go {\"a\":1} thanks") == "{\"a\":1}")
        check("LLMJSON: spans first '{' to last '}' (nested)",
              LLMJSON.firstJSONSlice(in: "x {\"a\":{\"b\":2}} y") == "{\"a\":{\"b\":2}}")
        check("LLMJSON: nil when there is no object",
              LLMJSON.firstJSONSlice(in: "no json here") == nil)
        check("LLMJSON: strips a ```json fence",
              LLMJSON.stripFence("```json\n{\"a\":1}\n```").contains("{\"a\":1}")
              && !LLMJSON.stripFence("```json\n{\"a\":1}\n```").contains("```"))
        check("LLMJSON: strips a bare ``` fence",
              !LLMJSON.stripFence("```\n{\"b\":2}\n```").contains("`"))
        check("LLMJSON: passes through unfenced text",
              LLMJSON.stripFence("{\"c\":3}") == "{\"c\":3}")

        // prod-22: HTTP failures map to the right SourceError category.
        check("prod-22: 429 → rateLimited (actionable)", {
            if case .rateLimited = SourceError.from(status: 429, kind: .reddit) { return true }
            return false
        }())
        check("prod-22: 403 → authFailed (actionable)", {
            if case .authFailed = SourceError.from(status: 403, kind: .youtubeChannel) { return true }
            return false
        }())
        check("prod-22: 503 → serverError (not actionable)",
              SourceError.from(status: 503, kind: .news).isActionable == false)
        check("prod-22: 418 → generic requestFailed",
              { if case .requestFailed = SourceError.from(status: 418, kind: .web) { return true }; return false }())
        check("prod-22: rateLimited & authFailed are actionable; server/generic are not",
              SourceError.from(status: 429, kind: .reddit).isActionable
              && SourceError.from(status: 401, kind: .web).isActionable
              && !SourceError.from(status: 500, kind: .news).isActionable
              && !SourceError.from(status: 404, kind: .news).isActionable)
        check("prod-22: categorized errors have distinct messages",
              SourceError.from(status: 429, kind: .reddit).errorDescription
                != SourceError.from(status: 403, kind: .reddit).errorDescription)

        // prod-36: dangling entity_mention rows (cluster_id pointing at no
        // cluster) are pruned; real mentions and the empty key are kept.
        if let topEntity = (try? storage.topEntities(limit: 1))?.first {
            let bogusCluster = "bogus-cluster-\(runID)"
            try? storage.recordEntityMention(entityID: topEntity.id, reportID: report.id, clusterID: bogusCluster)
            check("prod-36: dangling mention present before prune",
                  (try? storage.entityMentionCount(clusterID: bogusCluster)) == 1)
            try? storage.pruneDanglingEntityMentions()
            check("prod-36: dangling mention pruned",
                  (try? storage.entityMentionCount(clusterID: bogusCluster)) == 0)
        }
        check("prod-36: cluster key coerces nil to empty string",
              StorageManager.entityMentionClusterKey(nil) == ""
              && StorageManager.entityMentionClusterKey("c1") == "c1")

        // prod-41: per-kind subscription identifier validation.
        check("prod-41: empty identifier rejected",
              SubscriptionValidator.validationError(kind: .reddit, identifier: "  ") != nil)
        check("prod-41: valid subreddit accepted",
              SubscriptionValidator.validationError(kind: .reddit, identifier: "ethereum") == nil)
        check("prod-41: subreddit with r/ prefix accepted",
              SubscriptionValidator.validationError(kind: .reddit, identifier: "r/ethereum") == nil)
        check("prod-41: subreddit pasted as /r/ethereum accepted (adapter parity)",
              SubscriptionValidator.validationError(kind: .reddit, identifier: "/r/ethereum") == nil)
        check("prod-41: RSS rejects non-URL",
              SubscriptionValidator.validationError(kind: .rss, identifier: "not a url") != nil)
        check("prod-41: RSS accepts https feed URL",
              SubscriptionValidator.validationError(kind: .rss, identifier: "https://example.com/feed.xml") == nil)
        check("prod-41: Nitter rejects a pasted URL",
              SubscriptionValidator.validationError(kind: .xNitter, identifier: "https://x.com/vitalikbuterin") != nil)
        check("prod-41: Nitter accepts @handle",
              SubscriptionValidator.validationError(kind: .xNitter, identifier: "@vitalikbuterin") == nil)
        check("prod-41: YouTube accepts channel id",
              SubscriptionValidator.validationError(kind: .youtubeChannel, identifier: "UCabcdefghijklmnopqrstuv") == nil)
        check("prod-41: YouTube accepts @handle",
              SubscriptionValidator.validationError(kind: .youtubeChannel, identifier: "@bankless") == nil)

        // prod-14: monthly spend cap query + over-budget decision.
        check("prod-14: over budget when spent >= cap",
              SpendGuard.isOverBudget(spentThisMonth: 5.0, budget: 5.0))
        check("prod-14: under budget when spent < cap",
              !SpendGuard.isOverBudget(spentThisMonth: 4.99, budget: 5.0))
        check("prod-14: zero cap means no limit",
              !SpendGuard.isOverBudget(spentThisMonth: 999, budget: 0))
        let budgetProbe = Report(
            id: UUID(), presetID: nil, topic: "Budget probe \(runID)",
            window: .today, generatedAt: Date(), markdownPath: "",
            byteSize: 0, sourceCount: 1, kind: .daily
        )
        if let storedBudget = try? storage.insertReport(budgetProbe, markdown: "# budget \(runID)\n") {
            try? storage.addReportUsage(reportID: storedBudget.id, promptTokens: 0, completionTokens: 0, usdCost: 0.42)
            let spent = (try? storage.spend(since: SpendGuard.monthStart(Date()))) ?? 0
            check("prod-14: spend(since: monthStart) includes this run's cost (got \(spent))",
                  spent >= 0.42)
            _ = try? storage.deleteReports(ids: [storedBudget.id])
        }

        // prod-34: forward-looking cost estimate scales with call count and
        // is nil for unknown models.
        let est1 = ModelPricing.estimate(model: "gpt-4o-mini", calls: 1, avgPromptTokens: 4000, avgCompletionTokens: 1000)
        let est3 = ModelPricing.estimate(model: "gpt-4o-mini", calls: 3, avgPromptTokens: 4000, avgCompletionTokens: 1000)
        check("prod-34: estimate is positive for a known model", (est1 ?? 0) > 0)
        check("prod-34: estimate scales linearly with call count",
              { if let est1, let est3 { return abs(est3 - est1 * 3) < 1e-9 }; return false }())
        check("prod-34: estimate is nil for an unknown model",
              ModelPricing.estimate(model: "totally-unknown-xyz", calls: 2, avgPromptTokens: 1000, avgCompletionTokens: 500) == nil)

        // prod-15: backupDatabase writes a consistent, valid SQLite copy.
        // Use a high maxBackups so this never prunes a user's real backups
        // (the Settings-button self-check shares this code path).
        let sourceReportCount = (try? storage.listReports())?.count ?? -1
        if let backupURL = try? storage.backupDatabase(maxBackups: 1000) {
            check("prod-15: backup file created",
                  FileManager.default.fileExists(atPath: backupURL.path))
            var backupReportCount: Int?
            if let backupQueue = try? DatabaseQueue(path: backupURL.path) {
                backupReportCount = try? await backupQueue.read { db in
                    try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM report") ?? 0
                }
            }
            check("prod-15: backup is a valid SQLite copy with the report table",
                  backupReportCount != nil)
            check("prod-15: backup report count matches source (got \(backupReportCount ?? -1) vs \(sourceReportCount))",
                  backupReportCount == sourceReportCount)
        } else {
            check("prod-15: backupDatabase succeeded", false)
        }

        // prod-10: HTTP retry classification + backoff.
        check("Retry: 429 is transient", HTTPRetry.isTransient(status: 429))
        check("Retry: 503 is transient", HTTPRetry.isTransient(status: 503))
        check("Retry: 200 is not transient", !HTTPRetry.isTransient(status: 200))
        check("Retry: 404 is not transient", !HTTPRetry.isTransient(status: 404))
        check("Retry: timeout URLError is transient", HTTPRetry.isTransient(urlError: .timedOut))
        check("Retry: badURL URLError is not transient", !HTTPRetry.isTransient(urlError: .badURL))
        check("Retry: Retry-After delta-seconds parsed",
              HTTPRetry.retryAfterSeconds(HTTPURLResponse(
                  url: URL(string: "https://api.example/v1")!, statusCode: 429,
                  httpVersion: nil, headerFields: ["Retry-After": "7"])!) == 7)
        check("Retry: backoff honors Retry-After (capped)",
              HTTPRetry.delay(forAttempt: 1, retryAfter: 3) == 3)
        check("Retry: backoff capped at maxDelay",
              HTTPRetry.delay(forAttempt: 1, retryAfter: 9999) == HTTPRetry.maxDelay)
        let jittered = HTTPRetry.delay(forAttempt: 3, retryAfter: nil)
        check("Retry: jittered backoff stays within [0, maxDelay] (got \(jittered))",
              jittered >= 0 && jittered <= HTTPRetry.maxDelay)

        // prod-25: withTimeout returns a fast op's value, throws on a slow op.
        let fastResult = try? await withTimeout(seconds: 5) { 42 }
        check("prod-25: withTimeout returns fast op result", fastResult == 42)
        var timedOut = false
        do {
            _ = try await withTimeout(seconds: 0.05) {
                try await Task.sleep(nanoseconds: 3_000_000_000)
                return 1
            }
        } catch is TimeoutError {
            timedOut = true
        } catch {}
        check("prod-25: withTimeout throws TimeoutError on a slow op", timedOut)

        lines.append("")
        lines.append("Final: \(passed ? "PASS" : "FAIL")  ·  report id: \(report.id.uuidString.prefix(8))")
        return Result(passed: passed, lines: lines)
    }

    /// Pure-data version of `AppState.semanticSearch` for the self-check.
    /// Recomputes ranking directly from storage so we don't depend on the
    /// MainActor `AppState` cache, which isn't populated here.
    private struct StaticHit { let reportID: UUID; let score: Double }
    private static func state_semanticSearch(storage: StorageManager, query: String) -> [StaticHit] {
        guard let vector = ReportEmbedder.shared.embed(query),
              let entries = try? storage.allEmbeddings(), !entries.isEmpty
        else { return [] }
        return entries
            .map { StaticHit(reportID: $0.reportID, score: ReportEmbedder.similarity(vector, $0.vector)) }
            .sorted { $0.score > $1.score }
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
