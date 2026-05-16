import Foundation

/// Asks the LLM to fan out a multi-word topic into 2-4 disjoint sub-queries
/// optimized for source recall (Reddit / web / news / HN all reward
/// different phrasings). Single-token topics bypass the rewriter — fanning
/// out "ethereum" buys nothing.
struct QueryRewriter {
    let llm: LLMClient
    let model: String?

    static let minTopicWords = 3
    static let maxSubQueries = 4

    /// True if the rewriter should run for the given topic.
    static func shouldRewrite(topic: String) -> Bool {
        let words = topic
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .filter { !$0.isEmpty }
        return words.count >= minTopicWords
    }

    /// Rewrites a topic into sub-queries. Returns `[topic]` on any failure
    /// so the pipeline never fails because of the rewriter.
    func rewrite(topic: String) async -> [String] {
        guard QueryRewriter.shouldRewrite(topic: topic) else { return [topic] }

        let prompt = """
        You are helping a topic-briefing app fan out a user's request into 2-4 disjoint, recall-optimized sub-queries. The user gave you:

        Topic: "\(topic)"

        Produce a JSON object with a single field `subQueries`, an array of 2-4 strings, each a different angle on the topic. Keep each sub-query short (3-7 words). Do not include the original topic verbatim unless it's clearly the best single sub-query. Output ONLY the JSON object — no prose, no fence:

        {"subQueries": ["...", "..."]}
        """

        do {
            let response = try await llm.summarize(prompt: prompt, model: model)
            if let parsed = Self.extractJSON(response.text) {
                let unique = uniqueNonEmpty(parsed)
                return unique.isEmpty ? [topic] : Array(unique.prefix(Self.maxSubQueries))
            }
        } catch {
            // Fall through to baseline.
        }
        return [topic]
    }

    private struct Envelope: Decodable { let subQueries: [String] }

    /// Pulls the JSON object out of free-form text (model may have wrapped
    /// it in markdown despite instructions).
    private static func extractJSON(_ raw: String) -> [String]? {
        let candidate: String
        if let openRange = raw.range(of: "```"),
           let closeRange = raw.range(of: "```", range: openRange.upperBound..<raw.endIndex) {
            // strip optional ```json language tag
            var body = String(raw[openRange.upperBound..<closeRange.lowerBound])
            if body.hasPrefix("json") { body = String(body.dropFirst(4)) }
            candidate = body
        } else {
            candidate = raw
        }
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let data = trimmed.data(using: .utf8),
              let env = try? JSONDecoder().decode(Envelope.self, from: data)
        else { return nil }
        return env.subQueries
    }

    private func uniqueNonEmpty(_ subs: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for s in subs {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if seen.insert(key).inserted {
                out.append(trimmed)
            }
        }
        return out
    }
}
