import Foundation

/// Once a week per opt-in preset, synthesizes the last 7 days of daily
/// briefs into a meta-brief: longest-running storylines, what changed,
/// and what's worth watching next week (P5-6).
///
/// The result is written through `StorageManager.insertReport` with
/// `kind = .weeklyDigest`, so it shows up in History / FTS / exports /
/// audio brief alongside the daily reports — but is visually badged.
@MainActor
final class WeeklySynthesizer {
    private let storage: StorageManager
    private let llm: LLMClient
    private let model: String?

    init(storage: StorageManager, llm: LLMClient, model: String? = nil) {
        self.storage = storage
        self.llm = llm
        self.model = model
    }

    /// Build + persist a weekly digest for the given preset. Returns the
    /// stored `Report` or `nil` if there were no daily reports to synth.
    @discardableResult
    func synthesize(for preset: TopicPreset, at now: Date = Date()) async throws -> Report? {
        let dailies = (try? storage.dailyReports(forPreset: preset.id, withinDays: 7)) ?? []
        guard !dailies.isEmpty else { return nil }

        var blocks: [String] = []
        for r in dailies {
            let md = (try? storage.loadMarkdown(for: r)) ?? ""
            let clusters = (try? storage.clusters(for: r.id)) ?? []
            let clusterList = clusters.prefix(5).map { "  - \($0.headline): \($0.summary)" }.joined(separator: "\n")
            let tldr = WeeklySynthesizer.tldrLines(from: md).prefix(3)
                .map { "  - \($0)" }.joined(separator: "\n")
            blocks.append("""
            ## \(WeeklySynthesizer.shortDate(r.generatedAt)) — \(r.topic)
            TL;DR:
            \(tldr.isEmpty ? "  (none captured)" : tldr)
            Top clusters:
            \(clusterList.isEmpty ? "  (none captured)" : clusterList)
            """)
        }

        let entities = (try? storage.topEntities(limit: 30)) ?? []
        let entityList = entities.prefix(15)
            .map { "  - \($0.canonicalName) (\($0.kind.displayName), mentions: \($0.mentionCount))" }
            .joined(separator: "\n")

        let prompt = """
        You are writing a **weekly digest** for someone who already read the daily briefs below. Identify the *meta* — what threads ran across the week, what shifted, and what to watch next week.

        Write a single markdown document with EXACTLY these sections in this order:

        # Weekly digest — \(preset.name)
        _Week of \(WeeklySynthesizer.shortDate(now))_

        ## Storylines
        2–5 bullets, each a storyline that appeared across multiple days. Include "(X days)" where X is the number of distinct days it appeared.

        ## What changed this week
        2–4 bullets. Each one must describe a concrete shift between the start and end of the week: numbers that moved, claims that flipped, new entrants, resolved contradictions. Skip if nothing changed.

        ## To watch
        2–4 bullets. Open questions, recurring "Not covered" gaps, near-term catalysts.

        Rules:
        - ONLY use the daily briefs below. Do NOT invent.
        - Cite by date: `[May 14]`, `[May 16]`, etc.
        - Be ~300 words total.

        # Daily briefs (last 7 days)
        \(blocks.joined(separator: "\n\n"))

        # Recurring entities (top by mention count)
        \(entityList.isEmpty ? "(none yet)" : entityList)
        """

        let response = try await llm.summarize(prompt: prompt, model: model)
        let body = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }

        let usdCost = response.usage.flatMap { ModelPricing.cost(forModel: response.model, usage: $0) }
        let draft = Report(
            id: UUID(),
            presetID: preset.id,
            topic: "\(preset.name) — weekly digest",
            window: .last7Days,
            generatedAt: now,
            markdownPath: "",
            byteSize: Int64(body.utf8.count),
            sourceCount: dailies.count,
            readAt: nil,
            promptTokens: response.usage?.promptTokens,
            completionTokens: response.usage?.completionTokens,
            usdCost: usdCost,
            modelUsed: response.model,
            providerUsed: llm.providerName,
            kind: .weeklyDigest
        )
        let stored = try storage.insertReport(draft, markdown: body)
        try? storage.updatePresetLastWeekly(id: preset.id, at: now)
        try? storage.indexReportForSearch(stored.id, topic: stored.topic, body: body)
        return stored
    }

    /// True if a preset has weekly digests enabled AND its last digest
    /// (or first-ever daily report) is ≥ 7 days old.
    static func isDue(_ preset: TopicPreset, now: Date = Date()) -> Bool {
        guard preset.weeklyDigestEnabled else { return false }
        let last = preset.lastWeeklyAt ?? preset.createdAt
        return now.timeIntervalSince(last) >= 7 * 86_400
    }

    // MARK: - Helpers

    static func tldrLines(from markdown: String) -> [String] {
        var out: [String] = []
        var inTLDR = false
        for line in markdown.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("## tl;dr") || trimmed.lowercased().hasPrefix("## tldr") {
                inTLDR = true; continue
            }
            if inTLDR {
                if trimmed.hasPrefix("## ") { break }
                if trimmed.hasPrefix("- ") { out.append(String(trimmed.dropFirst(2))) }
            }
        }
        return out
    }

    static func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }
}
