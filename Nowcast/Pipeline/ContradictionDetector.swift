import Foundation

/// Second-pass LLM call that scans the clusters' claims for cross-source
/// disagreement: different numbers/dates/entities for the same fact. Off
/// by default — costs another LLM call per brief.
struct ContradictionDetector {
    let llm: LLMClient
    let model: String?

    static let minClaimsToScan = 5

    struct Contradiction: Codable, Hashable, Identifiable {
        let id: UUID
        let claimA: String
        let claimB: String
        let kind: String     // "numeric" | "date" | "entity"
        let severity: String // "low" | "medium" | "high"
        let note: String?

        init(id: UUID = UUID(), claimA: String, claimB: String, kind: String, severity: String, note: String?) {
            self.id = id
            self.claimA = claimA
            self.claimB = claimB
            self.kind = kind
            self.severity = severity
            self.note = note
        }
    }

    /// Detect contradictions across all claims in the given clusters.
    /// Returns an empty array on any error or thin input.
    func detect(in clusters: [BriefingResult.Cluster]) async -> [Contradiction] {
        await detectTracked(in: clusters).pairs
    }

    /// Result envelope with usage tokens so the pipeline can include the
    /// contradiction-pass spend in the report's cost accounting.
    /// FIX (codex review PRs #35, #46).
    struct TrackedDetection {
        let pairs: [Contradiction]
        let usage: LLMUsage?
        let model: String
    }

    func detectTracked(in clusters: [BriefingResult.Cluster]) async -> TrackedDetection {
        let claims = clusters.flatMap { cluster in
            cluster.claims.map { $0.text }
        }
        guard claims.count >= Self.minClaimsToScan else {
            return TrackedDetection(pairs: [], usage: nil, model: model ?? "")
        }

        let prompt = renderPrompt(claims: claims)
        do {
            let response = try await llm.summarize(prompt: prompt, model: model)
            return TrackedDetection(
                pairs: Self.parse(response.text),
                usage: response.usage,
                model: response.model
            )
        } catch {
            return TrackedDetection(pairs: [], usage: nil, model: model ?? "")
        }
    }

    /// Render the contradictions as a markdown section, ready to prepend
    /// to the visible body. Empty if no contradictions.
    static func renderMarkdown(_ contradictions: [Contradiction]) -> String? {
        guard !contradictions.isEmpty else { return nil }
        var lines: [String] = ["## ⚠ Sources disagree"]
        for c in contradictions {
            let badge: String
            switch c.severity {
            case "high": badge = "🔴"
            case "medium": badge = "🟡"
            default: badge = "⚪️"
            }
            lines.append("- \(badge) **\(c.kind.capitalized)**: “\(c.claimA)” vs “\(c.claimB)”" + (c.note.map { " — \($0)" } ?? ""))
        }
        return lines.joined(separator: "\n")
    }

    private func renderPrompt(claims: [String]) -> String {
        let numbered = claims.enumerated().map { "\($0+1). \($1)" }.joined(separator: "\n")
        return """
        You are checking a draft news briefing for cross-source factual disagreements. Below are the claims it makes. Identify pairs whose facts contradict each other (different numbers, different dates, conflicting entities, or claims that can't both be true).

        Claims:
        \(numbered)

        Output a JSON object with one field `pairs`, an array (possibly empty) of objects with these fields: `claim_a` (string, copy verbatim), `claim_b` (string, copy verbatim), `kind` ("numeric" | "date" | "entity"), `severity` ("low" | "medium" | "high"), and an optional `note` (≤ 18 words). Be strict — only emit a pair when there is a *real* disagreement, not a different angle. Output ONLY the JSON object:

        {"pairs": [{"claim_a": "...", "claim_b": "...", "kind": "numeric", "severity": "medium", "note": "..."}]}
        """
    }

    private struct Envelope: Decodable {
        let pairs: [Pair]
        struct Pair: Decodable {
            let claim_a: String
            let claim_b: String
            let kind: String
            let severity: String
            let note: String?
        }
    }

    private static func parse(_ raw: String) -> [Contradiction] {
        let candidate: String
        if let openRange = raw.range(of: "```"),
           let closeRange = raw.range(of: "```", range: openRange.upperBound..<raw.endIndex) {
            var body = String(raw[openRange.upperBound..<closeRange.lowerBound])
            if body.hasPrefix("json") { body = String(body.dropFirst(4)) }
            candidate = body
        } else {
            candidate = raw
        }
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let env = try? JSONDecoder().decode(Envelope.self, from: data)
        else { return [] }
        return env.pairs.map {
            Contradiction(
                claimA: $0.claim_a,
                claimB: $0.claim_b,
                kind: $0.kind,
                severity: $0.severity,
                note: $0.note
            )
        }
    }
}
