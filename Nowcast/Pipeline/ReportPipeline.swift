import Foundation

/// Orchestrates a single report: fetch from selected adapters, dedupe via
/// storage's seen-index, summarize via the configured LLM, write markdown +
/// DB row, return the new Report.
final class ReportPipeline {
    private let adapters: [SourceKind: SourceAdapter]
    private let storage: StorageManager
    private let llm: LLMClient
    private let model: String?

    init(adapters: [SourceAdapter], storage: StorageManager, llm: LLMClient, model: String? = nil) {
        var map: [SourceKind: SourceAdapter] = [:]
        for adapter in adapters { map[adapter.kind] = adapter }
        self.adapters = map
        self.storage = storage
        self.llm = llm
        self.model = model
    }

    /// Generate a report. Throws if no items are found at all (caller decides
    /// whether to surface that as "nothing new this run").
    func generate(topic: String,
                  window: TimeWindow,
                  sources: [SourceKind],
                  presetID: UUID? = nil,
                  subscriptions: [SourceSubscription] = []) async throws -> Report {
        // 1. Fetch from each requested adapter in parallel.
        let collected: [RawItem] = try await withThrowingTaskGroup(of: [RawItem].self) { group in
            for kind in sources {
                guard let adapter = adapters[kind] else { continue }
                group.addTask {
                    do {
                        return try await adapter.fetch(
                            query: topic,
                            window: window,
                            subscriptions: subscriptions.filter { $0.kind == kind }
                        )
                    } catch {
                        // One failed adapter shouldn't fail the whole report.
                        return []
                    }
                }
            }
            var all: [RawItem] = []
            for try await chunk in group { all.append(contentsOf: chunk) }
            return all
        }

        // 2. Dedupe within this run by URL hash, then against persistent seen-index.
        //    Note: we *check* the seen-index but do not record yet — recording
        //    only happens after a successful insert, otherwise a network
        //    failure would permanently blacklist items.
        let withinRunUnique = Self.dedupeWithinRun(collected)
        let fresh = try storage.filterUnseen(withinRunUnique, presetID: presetID)

        guard !fresh.isEmpty else {
            throw PipelineError.noFreshItems
        }

        // 2b. Materialize every surviving item into the `item` table so we
        //     can build downstream features (diff, timeline, trust, search)
        //     on a real per-item history instead of throwaway markdown.
        let itemIDsByHash = (try? storage.upsertItems(withinRunUnique)) ?? [:]
        let freshHashes = Set(fresh.map(\.urlHash))

        // 3. Build prompt and call the LLM.
        let prompt = BriefingPrompt.render(topic: topic, window: window, items: fresh)
        let response = try await llm.summarize(prompt: prompt, model: model)

        // 4. Wrap with a header and persist.
        let header = Self.headerMarkdown(topic: topic, window: window, fresh: fresh.count, total: collected.count)
        let markdown = header + "\n\n" + response.text

        let usdCost = response.usage.flatMap {
            ModelPricing.cost(forModel: response.model, usage: $0)
        }
        let draft = Report(
            id: UUID(),
            presetID: presetID,
            topic: topic,
            window: window,
            generatedAt: Date(),
            markdownPath: "",
            byteSize: Int64(markdown.utf8.count),
            sourceCount: fresh.count,
            readAt: nil,
            promptTokens: response.usage?.promptTokens,
            completionTokens: response.usage?.completionTokens,
            usdCost: usdCost,
            modelUsed: response.model,
            providerUsed: llm.providerName
        )
        let stored = try storage.insertReport(draft, markdown: markdown)

        // 5. Only now record the items as seen — guarantees retry-on-failure.
        try storage.recordSeen(fresh, presetID: presetID)

        // 6. Link items to this report so future runs / views can find them.
        try? storage.attachItemsToReport(stored.id,
                                         itemIDsByHash: itemIDsByHash,
                                         freshHashes: freshHashes)

        return stored
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
