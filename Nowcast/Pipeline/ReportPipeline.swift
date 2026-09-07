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
    private let entityExtractionEnabled: Bool
    private let counterpointsEnabled: Bool
    private let smartTitlesEnabled: Bool

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
         contradictionDetectionEnabled: Bool = false,
         entityExtractionEnabled: Bool = false,
         counterpointsEnabled: Bool = false,
         smartTitlesEnabled: Bool = false) {
        var map: [SourceKind: SourceAdapter] = [:]
        for adapter in adapters { map[adapter.kind] = adapter }
        self.adapters = map
        self.storage = storage
        self.llm = llm
        self.model = model
        self.queryRewritingEnabled = queryRewritingEnabled
        self.contradictionDetectionEnabled = contradictionDetectionEnabled
        self.entityExtractionEnabled = entityExtractionEnabled
        self.counterpointsEnabled = counterpointsEnabled
        self.smartTitlesEnabled = smartTitlesEnabled
    }

    /// Generate a report. Throws if no items are found at all (caller decides
    /// whether to surface that as "nothing new this run"). Optional
    /// `progress` callback fires with `PipelineStage` events so the UI can
    /// render a live timeline.
    func generate(topic: String,
                  window: TimeWindow,
                  sources: [SourceKind],
                  presetID: UUID? = nil,
                  subscriptions: [SourceSubscription] = [],
                  depth: BriefDepth = .standard,
                  tone: BriefTone = .neutral,
                  progress: (@Sendable (PipelineStage) -> Void)? = nil) async throws -> Report {
        @Sendable func emit(_ s: PipelineStage) { progress?(s) }
        emit(.started(topic: topic, sourceCount: sources.count))
        // 0. Optionally fan out the topic into 2-4 sub-queries. Single-
        //    token topics or rewriter-disabled config: just use the topic.
        //    The rewriter call's token usage rolls into the report's
        //    totals so cost analytics aren't understated.
        var auxUsage: LLMUsage = LLMUsage(promptTokens: 0, completionTokens: 0)
        var auxCost: Double = 0
        let subQueries: [String]
        if queryRewritingEnabled, QueryRewriter.shouldRewrite(topic: topic) {
            emit(.rewriting)
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
        //    count, error) for the source-health panel.
        // Fan-out only for *query-sensitive* adapters that actually
        // change their results based on the input string. Subscription-
        // only adapters (NitterAdapter, YouTubeChannelAdapter, RSS feeds)
        // ignore `query` and would return identical items per sub-query,
        // wasting network and API quota. Paid/quota'd query adapters
        // (YouTube search, Brave search) also see only the original topic
        // to avoid burning daily quota in a single hourly run.
        let querySensitive: Set<SourceKind> = [.hackerNews, .reddit, .news]
        let observationStartedAt = Date()
        let outcomes: [FetchOutcome] = await withTaskGroup(of: FetchOutcome.self) { group in
            for kind in sources {
                guard let adapter = adapters[kind] else { continue }
                emit(.fetching(kind))
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
                                // Redacted: this string is persisted to
                                // source_run and shown in the Health panel.
                                errorMessage: error.redactedDescription
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
        // Emit a per-source "fetched" event in stable display order.
        for outcome in outcomes {
            emit(.fetched(outcome.kind, itemCount: outcome.items.count))
        }

        // 2. Dedupe within this run by URL hash, then against persistent seen-index.
        //    Note: we *check* the seen-index but do not record yet — recording
        //    only happens after a successful insert, otherwise a network
        //    failure would permanently blacklist items.
        emit(.deduping(beforeCount: collected.count))
        let withinRunUnique = Self.dedupeWithinRun(collected)
        let fresh = try storage.filterUnseen(withinRunUnique, presetID: presetID)

        // Empty runs still contribute freshness evidence. Anchor them to this
        // preset's prior report, never another preset's most recent report.
        let healthAnchorID = try? storage.mostRecentPriorReport(
            presetID: presetID, topic: topic, before: Date())?.id
        if fresh.isEmpty {
            // Even though we'll throw, log the adapter outcomes first so
            // a stuck/dead source still shows up in the Health tab.
            if let anchor = healthAnchorID {
                recordSourceRuns(outcomes: outcomes,
                                 freshURLHashes: Set<String>(),
                                 reportID: anchor,
                                 observationStartedAt: observationStartedAt)
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
        //    similar headlines (personalization hint — mild signal).
        let avoidHint: String? = (try? storage.recentDismissedHeadlines())
            .flatMap(PreferenceHint.build(from:))
        let prompt = BriefingPrompt.render(
            topic: topic,
            window: window,
            items: fresh,
            avoidHint: avoidHint,
            depth: depth,
            tone: tone
        )
        emit(.llmRequested)
        let response = try await llm.summarize(prompt: prompt, model: model)
        emit(.llmReceived(tokens: response.usage?.totalTokens))

        // 3b. Try to extract the structured trailing JSON block. If the
        //     model didn't emit one, or it failed to parse, gracefully fall
        //     back to the visible markdown so the user still gets a brief.
        emit(.validating)
        let extracted = BriefingExtractor.extract(from: response.text)
        var validatedResult: BriefingResult? = extracted.result.map {
            CitationValidator.filter($0, againstInputs: fresh)
        }

        // 3b.1 Optional counterpoint pass. Mutates `validatedResult`
        //      in place so the new counterpoint/gap fields land in the DB
        //      and a rendered markdown section can be appended below.
        if counterpointsEnabled,
           let current = validatedResult, !current.clusters.isEmpty {
            emit(.writingCounterpoints)
            let agent = CounterpointAgent(llm: llm, model: model)
            // prod-13: track this aux call's tokens/cost into the run total.
            let tracked = await agent.annotateTracked(current, items: fresh)
            validatedResult = tracked.result
            if let u = tracked.usage {
                auxUsage = LLMUsage(
                    promptTokens: auxUsage.promptTokens + u.promptTokens,
                    completionTokens: auxUsage.completionTokens + u.completionTokens
                )
                auxCost += ModelPricing.cost(forModel: tracked.model, usage: u) ?? 0
            }
        }
        let counterpointSection: String? = validatedResult.flatMap {
            CounterpointAgent.renderMarkdownSection(for: $0)
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

        // 3d. Optional cross-source contradiction detection. This pass's
        //     token usage rolls into the report's cost/usage totals.
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
        emit(.writing)
        let header = Self.headerMarkdown(topic: topic, window: window, fresh: fresh.count, total: collected.count)
        // If the LLM emitted ONLY the JSON block with no surrounding
        // markdown (extractor strips both, leaving a whitespace-only
        // prefix), fall back to the raw response so the user never gets
        // an empty body / empty FTS row.
        let trimmedMarkdown = extracted.markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        let visibleBody = (extracted.result == nil || trimmedMarkdown.isEmpty)
            ? response.text
            : extracted.markdown
        let diffPrefix = diffSection.map { $0 + "\n\n" } ?? ""
        let contradictionPrefix = contradictionSection.map { $0 + "\n\n" } ?? ""
        let counterpointSuffix = counterpointSection ?? ""
        let markdown = header + "\n\n" + contradictionPrefix + diffPrefix + visibleBody + counterpointSuffix

        // P7-2: optional smart-title call. Best-effort; nil falls back to
        // topic. Runs BEFORE the cost rollup below so its tokens are counted
        // (prod-13 — previously this aux call was dropped from the total).
        let smartTitle: String?
        if smartTitlesEnabled,
           let validated = validatedResult,
           !validated.clusters.isEmpty {
            let titler = SmartTitler(llm: llm, model: model)
            let tracked = await titler.titleTracked(
                topic: topic,
                tldr: validated.tldr,
                clusterHeadlines: validated.clusters.map(\.headline)
            )
            smartTitle = tracked.title
            if let u = tracked.usage {
                auxUsage = LLMUsage(
                    promptTokens: auxUsage.promptTokens + u.promptTokens,
                    completionTokens: auxUsage.completionTokens + u.completionTokens
                )
                auxCost += ModelPricing.cost(forModel: tracked.model, usage: u) ?? 0
            }
        } else {
            smartTitle = nil
        }

        // FIX (codex review PRs #35/#45/#46) + prod-13: roll ALL auxiliary LLM
        // calls (query rewriter, contradiction detector, counterpoints,
        // smart-title) into the report's recorded tokens + cost so cost
        // analytics reflect *all* pre-insert spend, not just the briefing call.
        // (Entity extraction runs post-insert and is added via addReportUsage.)
        let mainUsage = response.usage
        let mainCost = mainUsage.flatMap {
            ModelPricing.cost(forModel: response.model, usage: $0)
        } ?? 0
        let totalPromptTokens = (mainUsage?.promptTokens ?? 0) + auxUsage.promptTokens
        let totalCompletionTokens = (mainUsage?.completionTokens ?? 0) + auxUsage.completionTokens
        let totalCost = mainCost + auxCost

        // P8-2: score cross-source agreement on the validated clusters so
        // the History row and menu bar can surface a "big story" badge
        // when many independent sources converge on one story.
        let bigStory: BigStoryScorer.Outcome = validatedResult.map(BigStoryScorer.score)
            ?? BigStoryScorer.Outcome(score: 0, headline: nil)

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
            providerUsed: llm.providerName,
            title: smartTitle,
            bigStoryScore: bigStory.score > 0 ? bigStory.score : nil,
            bigStoryHeadline: bigStory.headline,
            sentiment: validatedResult?.sentiment,
            sentimentRationale: validatedResult?.sentimentRationale
        )
        let stored = try storage.insertReport(draft, markdown: markdown)

        // 5. Record items as seen. `try?` — a failed seen-index write must
        //    NOT prevent items/clusters/FTS/source_run from being
        //    persisted, or the report becomes orphaned. A missed entry
        //    just costs one repeated story on the next run.
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

            // 7a. Cross-brief entity extraction. Always best-effort:
            //     ignore failures, ignore empty results, never block the
            //     report. Toggle in Settings keeps this opt-in for cost.
            if entityExtractionEnabled {
                emit(.enrichingEntities)
                let extractor = EntityExtractor(llm: llm, model: model)
                let entityUsage = await extractor.enrich(briefing: validated, reportID: stored.id, storage: storage)
                // prod-13: entity extraction runs after the report is inserted,
                // so fold its spend in via an update rather than the draft.
                if let u = entityUsage.usage {
                    try? storage.addReportUsage(
                        reportID: stored.id,
                        promptTokens: u.promptTokens,
                        completionTokens: u.completionTokens,
                        usdCost: ModelPricing.cost(forModel: entityUsage.model, usage: u) ?? 0
                    )
                }
            }
        }

        // 7b. Index the report + items into FTS5 for in-app search.
        try? storage.indexReportForSearch(stored.id, topic: topic, body: markdown)
        let storedItems = (try? storage.itemsForReport(stored.id)) ?? []
        try? storage.indexItemsForSearch(storedItems)

        // 7c. Embed for semantic search. Best effort — semantic
        //     search is a secondary surface; if the OS embedder is absent
        //     or vector computation fails, we silently skip and rely on
        //     keyword/FTS. Runs on the calling task, costing a handful of
        //     ms of CPU — small relative to LLM + network already in the
        //     critical path.
        let indexText = ReportEmbedder.makeIndexText(
            topic: topic,
            title: smartTitle,
            markdown: markdown
        )
        if let vector = ReportEmbedder.shared.embed(indexText) {
            try? storage.saveEmbedding(reportID: stored.id, vector: vector)
        }

        // 8. Record per-adapter outcomes for the source health panel.
        //    Each fresh URL is credited to the FIRST adapter that returned
        //    it (deterministic: `outcomes` order), so two adapters
        //    returning the same URL don't both get credit for one item.
        let freshURLHashSet = Set(fresh.map(\.urlHash))
        recordSourceRuns(outcomes: outcomes,
                         freshURLHashes: freshURLHashSet,
                         reportID: stored.id,
                         observationStartedAt: observationStartedAt)

        emit(.done(reportID: stored.id))
        return stored
    }

    private func recordSourceRuns(outcomes: [FetchOutcome],
                                  freshURLHashes: Set<String>,
                                  reportID: UUID,
                                  observationStartedAt: Date) {
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
                // Shared generation boundary allows cadence analysis to group
                // all sources/subqueries, including repeated no-fresh runs.
                startedAt: observationStartedAt,
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
