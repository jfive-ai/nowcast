import Foundation

/// Second-pass agent that reads a generated briefing and asks the model
/// to produce a steel-manned counter-argument and a "what's not covered"
/// gap per cluster (P5-3). Strict envelope; refuses to invent.
final class CounterpointAgent {
    struct Hit: Codable, Equatable {
        /// Matches the temporary `c1`, `c2`… labels assigned in the prompt,
        /// so the caller can map back to its real cluster ids.
        let cluster: String
        let counterpoint: String?
        let gap: String?
    }

    private let llm: LLMClient
    private let model: String?

    init(llm: LLMClient, model: String? = nil) {
        self.llm = llm
        self.model = model
    }

    /// Annotated briefing plus the call's token usage so the pipeline can
    /// fold this (otherwise-untracked) aux call into the report's cost (prod-13).
    struct TrackedAnnotation {
        let result: BriefingResult
        let usage: LLMUsage?
        let model: String
    }

    /// Returns a new `BriefingResult` with `counterpoint`/`gap` populated on
    /// the clusters where the agent had something to say. Best-effort: on
    /// any failure returns the input unchanged.
    func annotate(_ briefing: BriefingResult, items: [RawItem] = []) async -> BriefingResult {
        await annotateTracked(briefing, items: items).result
    }

    func annotateTracked(_ briefing: BriefingResult, items: [RawItem] = []) async -> TrackedAnnotation {
        guard !briefing.clusters.isEmpty else {
            return TrackedAnnotation(result: briefing, usage: nil, model: model ?? "")
        }

        let labels: [String] = briefing.clusters.indices.map { "c\($0 + 1)" }
        let clusterBlocks = zip(labels, briefing.clusters).map { label, c in
            let claimsBlock = c.claims.prefix(5).map { "    - \($0.text)" }.joined(separator: "\n")
            return """
            [\(label)] \(c.headline)
              summary: \(c.summary)
              claims:
            \(claimsBlock.isEmpty ? "    (none)" : claimsBlock)
            """
        }.joined(separator: "\n\n")

        let prompt = """
        You are a critical-reading coach. For each cluster below, give:
        1. The single strongest **counter-argument or steel-manned opposing view**
           — ONLY if a plausible one exists in or near the linked claims.
           Do NOT invent. If nothing plausible, set counterpoint to null.
        2. A one-sentence **gap**: what important context this cluster is
           NOT covering. If nothing missing, set gap to null.

        Rules:
        - At most 240 characters per counterpoint or gap.
        - Do not introduce facts that aren't already implied by the cluster.
        - Do not link to outside sources.

        Return ONLY a JSON object on the first line of your reply, no prose:
        {"hits": [
          {"cluster": "c1", "counterpoint": "…" | null, "gap": "…" | null}
        ]}

        # Clusters
        \(clusterBlocks)
        """

        let response: LLMResponse
        do {
            response = try await llm.summarize(prompt: prompt, model: model)
        } catch {
            return TrackedAnnotation(result: briefing, usage: nil, model: model ?? "")
        }

        let hits = Self.parse(response.text)
        guard !hits.isEmpty else {
            return TrackedAnnotation(result: briefing, usage: response.usage, model: response.model)
        }

        let byLabel: [String: Hit] = Dictionary(uniqueKeysWithValues: hits.map { ($0.cluster, $0) })
        var mutated = briefing
        for (idx, label) in labels.enumerated() {
            if let hit = byLabel[label] {
                mutated.clusters[idx].counterpoint = Self.cleanNull(hit.counterpoint)
                mutated.clusters[idx].gap = Self.cleanNull(hit.gap)
            }
        }
        return TrackedAnnotation(result: mutated, usage: response.usage, model: response.model)
    }

    static func parse(_ raw: String) -> [Hit] {
        guard let json = LLMJSON.firstJSONSlice(in: raw),
              let data = json.data(using: .utf8) else { return [] }
        struct Envelope: Decodable { let hits: [Hit] }
        return (try? JSONDecoder().decode(Envelope.self, from: data))?.hits ?? []
    }

    private static func cleanNull(_ s: String?) -> String? {
        guard let raw = s?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let lowered = raw.lowercased()
        if lowered == "null" || lowered == "n/a" || lowered == "none" { return nil }
        return raw
    }

    /// Append a markdown "## Counterpoints" section if any cluster has one.
    static func renderMarkdownSection(for briefing: BriefingResult) -> String? {
        let interesting = briefing.clusters.filter { $0.counterpoint != nil || $0.gap != nil }
        guard !interesting.isEmpty else { return nil }
        var out = "\n\n## Counterpoints\n"
        for c in interesting {
            out += "\n### \(c.headline)\n"
            if let cp = c.counterpoint {
                out += "- **Counter:** \(cp)\n"
            }
            if let gap = c.gap {
                out += "- **Not covered:** \(gap)\n"
            }
        }
        return out
    }
}
