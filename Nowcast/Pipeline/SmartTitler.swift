import Foundation

/// One-line headline generator that runs after a brief is produced (P7-2).
/// Returns nil on any failure — caller falls back to `report.topic`.
final class SmartTitler {
    private let llm: LLMClient
    private let model: String?

    init(llm: LLMClient, model: String? = nil) {
        self.llm = llm
        self.model = model
    }

    /// Returns a 6-12 word headline, or nil if the LLM call / parse failed.
    func title(topic: String, tldr: [String], clusterHeadlines: [String]) async -> String? {
        let body = tldr.prefix(4).enumerated()
            .map { "  - [\($0 + 1)] \($1)" }.joined(separator: "\n")
        let heads = clusterHeadlines.prefix(4)
            .map { "  - \($0)" }.joined(separator: "\n")

        let prompt = """
        Write a single 6-12 word **headline** that captures the most newsworthy item from the brief below. Rules:
        - Do NOT use the literal topic verbatim.
        - Headline only — no punctuation at the end, no quotes, no editorializing.
        - Concrete: name the entity / number / action.

        Return ONLY the headline on the very first line of your reply. No preamble.

        # Brief
        Topic: \(topic)
        TL;DR:
        \(body.isEmpty ? "  (none)" : body)
        Cluster headlines:
        \(heads.isEmpty ? "  (none)" : heads)

        Headline:
        """

        do {
            let response = try await llm.summarize(prompt: prompt, model: model)
            return Self.parse(response.text)
        } catch {
            return nil
        }
    }

    /// Take the first non-empty line, strip trailing punctuation/quotes.
    static func parse(_ raw: String) -> String? {
        for line in raw.components(separatedBy: "\n") {
            var trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            // Strip preambles the model might add despite instructions.
            for prefix in ["Headline:", "**Headline:**", "Title:", "**Title:**"] {
                if trimmed.lowercased().hasPrefix(prefix.lowercased()) {
                    trimmed = String(trimmed.dropFirst(prefix.count))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            trimmed = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’."))
            if trimmed.count >= 4 { return trimmed }
        }
        return nil
    }
}
