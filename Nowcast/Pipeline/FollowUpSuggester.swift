import Foundation

/// LLM-driven "what should I subscribe to next?" suggester. Takes
/// the report's TL;DR + cluster headlines plus the user's existing preset
/// names (to avoid duplicates) and returns up to 3 candidate presets the
/// user can one-click create.
final class FollowUpSuggester {
    struct Suggestion: Identifiable, Equatable, Codable {
        let id = UUID()
        let name: String
        let query: String
        let sources: [SourceKind]

        private enum CodingKeys: String, CodingKey { case name, query, sources }
    }

    private let llm: LLMClient
    private let model: String?

    init(llm: LLMClient, model: String? = nil) {
        self.llm = llm
        self.model = model
    }

    /// Build + return suggestions for the given report. Returns an empty
    /// array on any LLM or parse failure — the strip silently hides.
    func suggest(for report: Report,
                 tldr: [String],
                 clusterHeadlines: [String],
                 existingPresetNames: [String]) async -> [Suggestion] {
        let avoid = existingPresetNames.isEmpty
            ? "(no existing presets)"
            : existingPresetNames.map { "- \($0)" }.joined(separator: "\n")
        let body = tldr.prefix(5).enumerated()
            .map { "  - [\($0 + 1)] \($1)" }.joined(separator: "\n")
        let headlines = clusterHeadlines.prefix(6).enumerated()
            .map { "  - [c\($0 + 1)] \($1)" }.joined(separator: "\n")

        let prompt = """
        You're suggesting **3 follow-up topic presets** for a user who just read this brief on "\(report.topic)". Each suggestion should be a *related but distinct* topic the user might want to subscribe to on a recurring basis.

        Rules:
        - Each `query` must be at least one word different from "\(report.topic)" and from every other suggestion.
        - Each must be a topic, not a question.
        - Pick at most 3 sources from this set: hackerNews, reddit, rss, news, youtubeSearch, web, xNitter.
        - Don't duplicate any of the user's existing preset names:
        \(avoid)

        Return ONLY a JSON object on the first line of your reply:
        {"suggestions": [
          {"name": "...", "query": "...", "sources": ["news", "reddit"]}
        ]}

        # Brief just read
        Topic: \(report.topic)
        TL;DR:
        \(body.isEmpty ? "  (none)" : body)
        Cluster headlines:
        \(headlines.isEmpty ? "  (none)" : headlines)
        """

        do {
            let response = try await llm.summarize(prompt: prompt, model: model)
            return Self.parse(response.text)
        } catch {
            return []
        }
    }

    static func parse(_ raw: String) -> [Suggestion] {
        struct Envelope: Decodable {
            struct Hit: Decodable {
                let name: String
                let query: String
                let sources: [String]?
            }
            let suggestions: [Hit]
        }
        guard let decoded = LLMJSON.decode(Envelope.self, from: raw) else { return [] }
        // Tolerate the LLM emitting common aliases (`brave`, `nitter`,
        // `x`…) instead of SourceKind raw values, so suggestions don't
        // silently fall back to .hackerNews.
        let aliases: [String: SourceKind] = [
            "bravesearch": .web,
            "brave": .web,
            "nitter": .xNitter,
            "x": .xNitter,
            "twitter": .xNitter,
        ]
        return decoded.suggestions.prefix(3).map { hit in
            let sources = (hit.sources ?? []).compactMap { raw -> SourceKind? in
                if let exact = SourceKind(rawValue: raw) { return exact }
                return aliases[raw.lowercased()]
            }
            return Suggestion(
                name: hit.name.trimmingCharacters(in: .whitespacesAndNewlines),
                query: hit.query.trimmingCharacters(in: .whitespacesAndNewlines),
                sources: sources.isEmpty ? [.hackerNews] : sources
            )
        }
    }
}
