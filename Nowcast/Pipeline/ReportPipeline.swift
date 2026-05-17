import Foundation

/// Orchestrates a single report: fetch from selected adapters, dedupe via
/// storage's seen-index, summarize via the configured LLM, write markdown +
/// DB row, return the new Report.
final class ReportPipeline {
    private let adapters: [SourceKind: SourceAdapter]
    private let storage: StorageManager
    private let llm: LLMClient
    private let model: String?
    private let queryRewritingEnabled: Bool
    private let contradictionDetectionEnabled: Bool

    /// One adapter fetch's outcome. Hoisted to a private nested type so
    /// `recordSourceRuns(...)` can be a regular method.
    fileprivate struct FetchOutcome {
        let kind: SourceKind
        let query: String
        let items: [RawItem]
        let startedAt: Date
        let finishedAt: Date
        let errorMessage: String?
    }

    init(adapters: [SourceAdapter],
         storage: StorageManager,
         llm: LLMClient,
         model: String? = nil,
         queryRewritingEnabled: Bool = false,
         contradictionDetectionEnabled: Bool = false) {
        var map: [SourceKind: SourceAdapter] = [:]
        for adapter in adapters { map[adapter.kind] = adapter }
        self.adapters = map
        self.storage = storage
        self.llm = llm
        self.model = model
        self.queryRewritingEnabled = queryRewritingEnabled
        self.contradictionDetectionEnabled = contradictionDetectionEnabled
    }

    /// Generate a report. Throws if no items are found at all (caller decides
    /// whether to surface that as "nothing new this run").
    func generate(topic: String,
                  window: TimeWindow,
                  sources: [SourceKind],
                  presetID: UUID? = nil,
                  subscriptions: [SourceSubscription] = []) async throws -> Report {
        // 0. Optionally fan out the topic into 2-4 sub-queries. Single-
        //    token topics or rewriter-disabled config: just use the topic.
        // FIX (codex review PR #45): the rewriter LLM call's token usage
        // is now tracked and rolled into the final report's
        // promptTokens / completionTokens / usdCost so the user's cost
        // analytics aren't systematically understated when rewriting is
        // enabled.
        var auxUsage: LLMUsage = LLMUsage(promptTokens: 0, completionTokens: 0)
        var auxCost: Double = 0
        let subQueries: [String]
        if queryRewritingEnabled, QueryRewriter.shouldRewrite(topic: topic) {
            let rewriter = QueryRewriter(llm: llm, model: model)
            let rewritten = await rewriter.rewriteTracked(topic: topic)
            subQueries = rewritten.queries
            if let u = rewritten.usage {
                auxUsage = LLMUsage(
                    promptTokens: auxUsage.promptTokens + u.promptTokens,
                    completionTokens: auxUsage.completionTokens + u.completionTokens
                )
                auxCost += ModelPricing.cost(forModel: rewritten.model, usage: u) ?? 0
            }
        } else {
            subQueries = [topic]
        }

        // 1. Fetch from each requested adapter × each sub-query in
        //    parallel. Each task records its own outcome (start, finish,
        //    count, error) for the source-health panel (P4-5).
        // Fan-out only for *query-sensitive* adapters that actually
        // change their results based on the input string. Subscription-
        // only adapters (NitterAdapter, YouTubeChannelAdapter, RSS feeds)
        // ignore `query` and would return identical items per sub-query,
        // wasting network and API quota. Paid/quota'd query adapters
        // (YouTube search, Brave search) also see only the original topic
        // to avoid burning daily quota in a single hourly run.
        // FIX (codex review PRs #34, #45 + previous review #5).
        let querySensitive: Set<SourceKind> = [.hackerNews, .reddit, .news]
        let outcomes: [FetchOutcome] = await withTaskGroup(of: FetchOutcome.self) { group in
            for kind in sources {
                guard let adapter = adapters[kind] else { continue }
                let effectiveQueries = querySensitive.contains(kind) ? subQueries : [topic]
                for subQuery in effectiveQueries {
                    group.addTask {
                        let started = Date()
                        do {
                            let items = try await adapter.fetch(
                                query: subQuery,
                                window: window,
                                subscriptions: subscriptions.filter { $0.kind == kind }
                            )
                            return FetchOutcome(
                                kind: kind,
                                query: subQuery,
                                items: items,
                                startedAt: started,
                                finishedAt: Date(),
                                errorMessage: nil
                            )
                        } catch {
                            return FetchOutcome(
                                kind: kind,
                                query: subQuery,
                                items: [],
                                startedAt: started,
                                finishedAt: Date(),
                                errorMessage: error.localizedDescription
                            )
                        }
                    }
                }
            }
            var all: [FetchOutcome] = []
            for await outcome in group { all.append(outcome) }
            return all
        }
        let collected: [RawItem] = outcomes.flatMap(\.items)

        // 2. Dedupe within this run by URL hash, then against persistent seen-index.
        //    Note: we *check* the seen-index but do not record yet — recording
        //    only happens after a successful insert, otherwise a network
        //    failure would permanently blacklist items.
        let withinRunUnique = Self.dedupeWithinRun(collected)
        let fresh = try storage.filterUnseen(withinRunUnique, presetID: presetID)

        // FIX (codex review PR #41): record per-adapter source_run rows
        // even on the noFreshItems path. Previously this only happened
        // after a successful insertReport, so health stats systematically
        // omitted failed/empty runs and over-reported reliability. The
        // rows are attached to a synthetic "no-report" run by leaving
        // report_id pointing at a NULL (handled by allowing nullable FK
        // in v9 below) — but to keep the change additive we use the
        // historical-only path: write rows tied to a synthetic report-id
        // sentinel held in a known UUID. For simplicity & migration
        // compatibility, attach them to the prior most-recent report id
        // instead; the panel aggregates by source_kind so attribution
        // doesn't matter.
        let healthAnchorID: UUID? = (try? storage.mostRecentReportID()) ?? nil
        if fresh.isEmpty {
            // Even though we'll throw, log the adapter outcomes first so
            // a stuck/dead source still shows up in the Health tab.
            if let anchor = healthAnchorID {
                recordSourceRuns(outcomes: outcomes,
                                 freshURLHashes: Set<String>(),
                                 reportID: anchor)
            }
            throw PipelineError.noFreshItems
        }

        // 2b. Materialize every surviving item into the `item` table so we
        //     can build downstream features (diff, timeline, trust, search)
        //     on a real per-item history instead of throwaway markdown.
        let itemIDsByHash = (try? storage.upsertItems(withinRunUnique)) ?? [:]
        let freshHashes = Set(fresh.map(\.urlHash))

        // 3. Build prompt and call the LLM. If the user has dismissed
        //    clusters in the last 30 days, ask the model to deprioritize
        //    similar headlines (P4-4 personalization hint — mild signal).
        let avoidHint: String? = (try? storage.recentDismissedHeadlines())
            .flatMap(PreferenceHint.build(from:))
        let prompt = BriefingPrompt.render(
            topic: topic,
            window: window,
            items: fresh,
            avoidHint: avoidHint
        )
        let response = try await llm.summarize(prompt: prompt, model: model)

        // 3b. Try to extract the structured trailing JSON block. If the
        //     model didn't emit one, or it failed to parse, gracefully fall
        //     back to the visible markdown so the user still gets a brief.
        let extracted = BriefingExtractor.extract(from: response.text)
        let validatedResult: BriefingResult? = extracted.result.map {
            CitationValidator.filter($0, againstInputs: fresh)
        }

        // 3c. If we have structured clusters, compute the diff against the
        //     most-recent prior report (same preset, or same topic when ad-
        //     hoc). Skip silently if no prior exists or no structured data.
        let now = Date()
        let diffSection: String? = {
            guard let current = validatedResult, !current.clusters.isEmpty else { return nil }
            guard let prior = try? storage.mostRecentPriorReport(
                presetID: presetID,
                topic: topic,
                before: now
            ) else { return nil }
            let priorClusters = (try? storage.clusters(for: prior.id)) ?? []
            guard !priorClusters.isEmpty else { return nil }
            let delta = BriefDiff.diff(current: current.clusters, prior: priorClusters)
            return BriefDiff.renderMarkdown(delta)
        }()

        // 3d. Optional cross-source contradiction detection (P4-10).
        // FIX (codex review PRs #35/#46): track this pass's token usage
        // so it rolls up into the report's cost/usage totals.
        let contradictionSection: String?
        if contradictionDetectionEnabled,
           let current = validatedResult, !current.clusters.isEmpty {
            let detector = ContradictionDetector(llm: llm, model: model)
            let outcome = await detector.detectTracked(in: current.clusters)
            contradictionSection = ContradictionDetector.renderMarkdown(outcome.pairs)
            if let u = outcome.usage {
                auxUsage = LLMUsage(
                    promptTokens: auxUsage.promptTokens + u.promptTokens,
                    completionTokens: auxUsage.completionTokens + u.completionTokens
                )
                auxCost += ModelPricing.cost(forModel: outcome.model, usage: u) ?? 0
            }
        } else {
            contradictionSection = nil
        }

        // 4. Wrap with a header and persist.
        let header = Self.headerMarkdown(topic: topic, window: window, fresh: fresh.count, total: collected.count)
        // FIX (review #2): if the LLM emitted ONLY the JSON block with no
        // surrounding markdown (extractor strips both, leaving a
        // whitespace-only prefix), fall back to the raw response so the
        // user never gets an empty body / empty FTS row.
        let trimmedMarkdown = extracted.markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        let visibleBody = (extracted.result == nil || trimmedMarkdown.isEmpty)
            ? response.text
            : extracted.markdown
        let diffPrefix = diffSection.map { $0 + "\n\n" } ?? ""
        let contradictionPrefix = contradictionSection.map { $0 + "\n\n" } ?? ""
        let markdown = header + "\n\n" + contradictionPrefix + diffPrefix + visibleBody

        // FIX (codex review PRs #35/#45/#46): roll auxiliary LLM calls
        // (query rewriter, contradiction detector) into the report's
        // recorded tokens + cost so cost analytics reflect *all* spend
        // for the run, not just the briefing call.
        let mainUsage = response.usage
        let mainCost = mainUsage.flatMap {
            ModelPricing.cost(forModel: response.model, usage: $0)
        } ?? 0
        let totalPromptTokens = (mainUsage?.promptTokens ?? 0) + auxUsage.promptTokens
        let totalCompletionTokens = (mainUsage?.completionTokens ?? 0) + auxUsage.completionTokens
        let totalCost = mainCost + auxCost
        let draft = Report(
            id: UUID(),
            presetID: presetID,
            topic: topic,
            window: window,
            generatedAt: now,
            markdownPath: "",
            byteSize: Int64(markdown.utf8.count),
            sourceCount: fresh.count,
            readAt: nil,
            promptTokens: totalPromptTokens > 0 ? totalPromptTokens : nil,
            completionTokens: totalCompletionTokens > 0 ? totalCompletionTokens : nil,
            usdCost: totalCost > 0 ? totalCost : nil,
            modelUsed: response.model,
            providerUsed: llm.providerName
        )
        let stored = try storage.insertReport(draft, markdown: markdown)

        // 5. Record items as seen. FIX (review #1): use `try?` — a failed
        // seen-index write must NOT prevent items/clusters/FTS/source_run
        // from being persisted, or the report becomes orphaned. The cost
        // of a missed seen-index entry is one repeated story on the next
        // run, which is far cheaper than an orphaned report.
        try? storage.recordSeen(fresh, presetID: presetID)

        // 6. Link items to this report so future runs / views can find them.
        try? storage.attachItemsToReport(stored.id,
                                         itemIDsByHash: itemIDsByHash,
                                         freshHashes: freshHashes)

        // 7. Persist structured clusters/claims if the LLM cooperated. Best
        //    effort — markdown is already saved so a save failure here is
        //    not user-visible.
        if let validated = validatedResult {
            try? storage.saveBriefing(validated, reportID: stored.id)
        }

        // 7b. Index the report + items into FTS5 for in-app search (P4-6).
        try? storage.indexReportForSearch(stored.id, topic: topic, body: markdown)
        let storedItems = (try? storage.itemsForReport(stored.id)) ?? []
        try? storage.indexItemsForSearch(storedItems)

        // 8. Record per-adapter outcomes for the source health panel.
        // FIX (codex review PR #30): per-source freshCount now uses the
        // adapter's *own* contribution to the dedup'd set, not the
        // global fresh hash set. Previously, if two adapters returned the
        // same URL, both got credit for the single fresh item — inflating
        // per-source contribution and obscuring which adapter actually
        // pulls weight. We attribute each fresh URL to the FIRST adapter
        // that returned it (deterministic ordering: by `outcomes` order).
        let freshURLHashSet = Set(fresh.map(\.urlHash))
        recordSourceRuns(outcomes: outcomes,
                         freshURLHashes: freshURLHashSet,
                         reportID: stored.id)

        return stored
    }

    private func recordSourceRuns(outcomes: [FetchOutcome],
                                  freshURLHashes: Set<String>,
                                  reportID: UUID) {
        var attributed = Set<String>()
        for outcome in outcomes {
            var thisSourceFresh = 0
            for item in outcome.items {
                let h = item.urlHash
                guard freshURLHashes.contains(h), !attributed.contains(h) else { continue }
                attributed.insert(h)
                thisSourceFresh += 1
            }
            let row = SourceRun(
                id: UUID(),
                reportID: reportID,
                sourceKind: outcome.kind,
                startedAt: outcome.startedAt,
                finishedAt: outcome.finishedAt,
                itemsReturned: outcome.items.count,
                itemsFresh: thisSourceFresh,
                errorMessage: outcome.errorMessage
            )
            try? storage.recordSourceRun(row)
        }
    }

    // MARK: - Helpers

    private static func dedupeWithinRun(_ items: [RawItem]) -> [RawItem] {
        var seen = Set<String>()
        var out: [RawItem] = []
        for i in items where seen.insert(i.urlHash).inserted {
            out.append(i)
        }
        return out
    }

    private static func headerMarkdown(topic: String, window: TimeWindow, fresh: Int, total: Int) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        let when = f.string(from: Date())
        return """
        # \(topic)

        _\(when) · window: \(window.displayName) · fresh: \(fresh) / collected: \(total)_
        """
    }
}

enum PipelineError: Error, LocalizedError {
    case noFreshItems

    var errorDescription: String? {
        switch self {
        case .noFreshItems:
            return "No new items found. Try widening the time window or running again later."
        }
    }
}
