import Foundation

/// Asks the configured LLM for a short list of plausible source
/// subscriptions for a topic. Output is parsed back into
/// `SourceSubscription` candidates the user can one-click-add.
struct SourceSuggester {
    private let llm: LLMClient

    init(llm: LLMClient) {
        self.llm = llm
    }

    func suggest(topic: String) async throws -> [SourceSubscription] {
        let trimmed = topic.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        let prompt = Self.prompt(for: trimmed)
        let response = try await llm.summarize(prompt: prompt, model: nil)
        return Self.parse(response.text)
    }

    static func prompt(for topic: String) -> String {
        """
        Suggest 5 specific source subscriptions for the topic "\(topic)".

        Each entry MUST be a real, currently-active source the user can subscribe to.
        Prefer high-signal feeds, not generic "best of the web" rollups.

        Reply with a JSON array of objects with EXACTLY these fields, and nothing else:
        - "kind": one of "reddit", "rss", "youtubeChannel"
        - "identifier": for reddit, the subreddit name without /r/.
                       For rss, the absolute feed URL.
                       For youtubeChannel, the @handle (preferred) or UC channel id.
        - "label": short human-readable name (≤ 40 chars).

        Example shape:
        [
          {"kind":"reddit","identifier":"ethereum","label":"r/ethereum"},
          {"kind":"rss","identifier":"https://blog.ethereum.org/feed.xml","label":"Ethereum Foundation"},
          {"kind":"youtubeChannel","identifier":"@bankless","label":"Bankless"}
        ]

        Output only the JSON array. Do not wrap it in markdown code fences.
        """
    }

    static func parse(_ raw: String) -> [SourceSubscription] {
        let cleaned = stripCodeFence(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleaned.data(using: .utf8) else { return [] }

        struct Suggestion: Decodable {
            let kind: String
            let identifier: String
            let label: String
        }
        guard let suggestions = try? JSONDecoder().decode([Suggestion].self, from: data) else {
            return []
        }

        return suggestions.compactMap { s -> SourceSubscription? in
            guard let kind = mapKind(s.kind),
                  !s.identifier.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return SourceSubscription(
                kind: kind,
                identifier: s.identifier.trimmingCharacters(in: .whitespaces),
                label: s.label.trimmingCharacters(in: .whitespaces)
            )
        }
    }

    private static func mapKind(_ raw: String) -> SourceKind? {
        switch raw.lowercased() {
        case "reddit":         return .reddit
        case "rss":            return .rss
        case "youtubechannel", "youtube_channel", "youtube":
            return .youtubeChannel
        default: return nil
        }
    }

    /// LLMs sometimes add ```json ... ``` despite being told not to.
    private static func stripCodeFence(_ raw: String) -> String {
        var s = raw
        if let r = s.range(of: "```") {
            s = String(s[r.upperBound...])
            // Drop a leading "json\n" if present.
            if s.lowercased().hasPrefix("json") {
                s = String(s.dropFirst(4))
            }
            if let end = s.range(of: "```") {
                s = String(s[..<end.lowerBound])
            }
        }
        return s
    }
}
