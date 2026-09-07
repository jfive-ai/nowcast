import Foundation

/// Pulls a flat list of named entities out of a `BriefingResult` and
/// persists them via `StorageManager`. Best-effort: any failure
/// degrades to a rule-based fallback rather than aborting the report.
final class EntityExtractor {
    struct Extracted: Codable, Equatable {
        let name: String
        let kind: Entity.Kind
        /// Optional cluster id this entity was lifted from.
        let clusterID: String?
    }

    private let llm: LLMClient?
    private let model: String?

    init(llm: LLMClient?, model: String? = nil) {
        self.llm = llm
        self.model = model
    }

    /// Runs the extractor end-to-end: calls the LLM (or rule fallback),
    /// upserts each entity, records mentions against `reportID`. Swallows
    /// all errors — the caller treats this as fire-and-forget enrichment.
    /// Usage of the (otherwise-untracked) entity-extraction LLM call so the
    /// pipeline can fold it into the report's cost (prod-13). nil when the
    /// rule-based fallback ran (no LLM call).
    struct TrackedUsage {
        let usage: LLMUsage?
        let model: String
    }

    @discardableResult
    func enrich(briefing: BriefingResult,
                reportID: UUID,
                storage: StorageManager) async -> TrackedUsage {
        let tracked = await extractTracked(briefing: briefing)
        let extracted = tracked.hits
        guard !extracted.isEmpty else { return TrackedUsage(usage: tracked.usage, model: tracked.model) }
        // FIX (codex review PR #67 P2): `saveBriefing` stores cluster.id
        // as `"<reportID>:<briefingClusterID>"` so foreign joins succeed.
        // Apply the same prefix here so entity_mention.cluster_id matches.
        for hit in extracted {
            do {
                let entityID = try storage.upsertEntity(name: hit.name, kind: hit.kind)
                let scopedClusterID = hit.clusterID.map { "\(reportID.uuidString):\($0)" }
                try storage.recordEntityMention(
                    entityID: entityID,
                    reportID: reportID,
                    clusterID: scopedClusterID
                )
            } catch {
                // Mention persistence failure is non-fatal for the report.
            }
        }
        return TrackedUsage(usage: tracked.usage, model: tracked.model)
    }

    /// Returns deduped, normalized entities. Tries the LLM first; falls
    /// back to a tiny rule-based extractor if the LLM call fails or no
    /// LLM is configured.
    func extract(briefing: BriefingResult) async -> [Extracted] {
        await extractTracked(briefing: briefing).hits
    }

    /// Same as `extract` but also returns the LLM call's token usage (nil for
    /// the rule-based fallback) so the pipeline can fold it into report cost.
    func extractTracked(briefing: BriefingResult) async -> (hits: [Extracted], usage: LLMUsage?, model: String) {
        if let llm {
            do {
                let r = try await llmExtractTracked(briefing: briefing, llm: llm)
                if !r.hits.isEmpty { return (Self.deduplicate(r.hits), r.usage, r.model) }
            } catch {
                // fall through to rules
            }
        }
        return (Self.deduplicate(Self.ruleBased(briefing: briefing)), nil, model ?? "")
    }

    // MARK: - LLM path

    private func llmExtractTracked(briefing: BriefingResult, llm: LLMClient) async throws -> (hits: [Extracted], usage: LLMUsage?, model: String) {
        let inputs = briefing.clusters.enumerated().map { idx, c in
            "[c\(idx + 1)] \(c.headline): \(c.summary)"
        }.joined(separator: "\n")

        let prompt = """
        Extract a flat list of named entities from the briefing clusters below.

        Allowed `kind` values:
        - person  — individuals
        - org     — companies, foundations, governments, regulators
        - project — protocols, products, codenames, named systems
        - topic   — tickers, asset names, hash-tag-like topics

        Rules:
        - Use canonical names ("Ethereum", not "ETH the network").
        - Skip generic words ("user", "developer", "today").
        - Skip if no clear entity exists.
        - At most 12 entities total.

        Return ONLY a JSON object on the very first line of your reply, no prose:
        {"entities": [{"name": "...", "kind": "person|org|project|topic", "cluster": "c1|c2|..."}]}

        # Clusters
        \(inputs)
        """

        let response = try await llm.summarize(prompt: prompt, model: model)
        let hits = Self.parseEnvelope(response.text, clusters: briefing.clusters)
        return (hits, response.usage, response.model)
    }

    static func parseEnvelope(_ raw: String, clusters: [BriefingResult.Cluster]) -> [Extracted] {
        struct Envelope: Decodable {
            struct Hit: Decodable {
                let name: String
                let kind: String
                let cluster: String?
            }
            let entities: [Hit]
        }

        guard let decoded = LLMJSON.decode(Envelope.self, from: raw) else { return [] }
        let clusterIDByLabel: [String: String] = Dictionary(
            uniqueKeysWithValues: clusters.enumerated().map { (idx, c) in ("c\(idx + 1)", c.id) }
        )
        return decoded.entities.compactMap { hit in
            guard let kind = Entity.Kind(rawValue: hit.kind.lowercased()) else { return nil }
            let trimmedName = hit.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { return nil }
            let cid = hit.cluster.flatMap { clusterIDByLabel[$0] }
            return Extracted(name: trimmedName, kind: kind, clusterID: cid)
        }
    }

    // MARK: - Rule-based fallback

    /// Extract Title-Cased phrases of length 1–3 words. Drops a small
    /// stop-list, treats $TICKER and ALLCAPS-only as `.topic`. Crude but
    /// gives the feature a non-empty result on the most common topics
    /// (ETH, EigenLayer, etc.) when no LLM is available.
    static func ruleBased(briefing: BriefingResult) -> [Extracted] {
        var hits: [Extracted] = []
        let stopWords: Set<String> = [
            "The", "This", "That", "Today", "Yesterday", "Week", "Month",
            "Sources", "Source", "Brief", "Item", "Items", "News",
            "Update", "Story", "Stories", "Time",
        ]
        for cluster in briefing.clusters {
            let body = "\(cluster.headline)\n\(cluster.summary)"

            // $TICKER style
            for match in Self.tickerRegex.matches(in: body, range: NSRange(body.startIndex..., in: body)) {
                if let r = Range(match.range, in: body) {
                    let token = String(body[r]).trimmingCharacters(in: CharacterSet(charactersIn: "$ "))
                    hits.append(Extracted(name: token, kind: .topic, clusterID: cluster.id))
                }
            }

            // Title-cased runs
            let tokens = body.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
            var i = 0
            while i < tokens.count {
                let tok = tokens[i]
                if Self.isTitleCased(tok), !stopWords.contains(tok) {
                    var run = [tok]
                    var j = i + 1
                    while j < tokens.count, Self.isTitleCased(tokens[j]), !stopWords.contains(tokens[j]) {
                        run.append(tokens[j]); j += 1
                        if run.count >= 3 { break }
                    }
                    let phrase = run.joined(separator: " ")
                    if phrase.count >= 3 {
                        hits.append(Extracted(name: phrase, kind: Self.guessKind(phrase), clusterID: cluster.id))
                    }
                    i = j
                } else {
                    i += 1
                }
            }
        }
        return hits
    }

    private static let tickerRegex: NSRegularExpression = {
        // `$AAA` or `$AAAA` style tickers (2–6 uppercase letters)
        return (try? NSRegularExpression(pattern: #"\$[A-Z]{2,6}\b"#)) ?? NSRegularExpression()
    }()

    private static func isTitleCased(_ s: String) -> Bool {
        guard let first = s.first else { return false }
        guard first.isUppercase else { return false }
        guard s.count >= 2 else { return false }
        // All-caps tokens count as topic-like — keep them, but classifier
        // will tag them as .topic.
        return true
    }

    private static func guessKind(_ phrase: String) -> Entity.Kind {
        if phrase.uppercased() == phrase, phrase.count <= 6 { return .topic }
        if phrase.split(separator: " ").count >= 2 {
            // Two-word title-cased phrase: likely person or project. Default to project.
            return .project
        }
        // Single word: most often a project / org name (e.g., "Ethereum", "Reuters").
        return .project
    }

    // MARK: - Dedup

    static func deduplicate(_ hits: [Extracted]) -> [Extracted] {
        var seen: Set<String> = []
        var out: [Extracted] = []
        for hit in hits {
            let key = "\(hit.name.lowercased())|\(hit.kind.rawValue)|\(hit.clusterID ?? "")"
            if seen.insert(key).inserted { out.append(hit) }
        }
        return out
    }
}
