#if DEBUG
import Foundation

/// DEBUG-only stand-in for an LLM client. Returns a canned response that
/// matches the exact format the production prompt asks for: visible
/// markdown + a `<!-- briefing-json -->` fenced JSON footer. Used by the
/// in-app self-check to exercise every Phase-4 code path without spending
/// a cent on real model calls.
struct MockLLMClient: LLMClient {
    let providerName = "Mock"
    let defaultModel = "mock-1"

    /// Builds a briefing whose citations echo the *actual* input URLs found
    /// in the prompt. The production `CitationValidator` drops any cluster
    /// whose citations don't match an input item, so a fixed-URL canned brief
    /// silently fails whenever the caller's items use different URLs (e.g. the
    /// self-check namespaces item URLs per run). Echoing the prompt's URLs
    /// keeps the mock valid for any input while preserving stable cluster ids
    /// (`c1`/`c2`) that the entity / counterpoint envelopes key off.
    static func briefing(citingURLsFrom prompt: String) -> String {
        let urls = inputURLs(in: prompt)
        let a = urls.first ?? "https://mock.example/one"
        let b = urls.dropFirst().first ?? a
        return """
        ## TL;DR
        - Mock cluster A captured.
        - Mock cluster B captured.
        - No-op signal section.

        ## Stories

        ### Mock cluster A
        A short summary of the first synthetic cluster. Numbers: $42 outflows.

        Sources:
        - [Item one](\(a))

        ### Mock cluster B
        A short summary of the second synthetic cluster.

        Sources:
        - [Item two](\(b))

        ## Signal
        Synthetic signal for self-check.

        ## Sources
        - Hacker News
          - [Item one](\(a))
          - [Item two](\(b))

        <!-- briefing-json -->
        ```json
        {
          "tldr": [
            "Mock cluster A captured.",
            "Mock cluster B captured.",
            "No-op signal section."
          ],
          "clusters": [
            {
              "id": "c1",
              "headline": "Mock cluster A",
              "summary": "A short summary of the first synthetic cluster.",
              "claims": [
                { "text": "Outflows totaled $42.", "citations": ["\(a)"] }
              ],
              "citations": ["\(a)"]
            },
            {
              "id": "c2",
              "headline": "Mock cluster B",
              "summary": "A short summary of the second synthetic cluster.",
              "claims": [
                { "text": "Pectra activation window confirmed.", "citations": ["\(b)"] }
              ],
              "citations": ["\(b)"]
            }
          ],
          "signal": "Synthetic signal for self-check.",
          "low_confidence": false
        }
        ```
        """
    }

    /// Pulls the `- url: <…>` lines the briefing prompt emits for each input
    /// item, in order, de-duplicated.
    static func inputURLs(in prompt: String) -> [String] {
        var seen = Set<String>()
        var urls: [String] = []
        for line in prompt.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- url:") else { continue }
            let value = trimmed.dropFirst("- url:".count).trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty, seen.insert(value).inserted else { continue }
            urls.append(value)
        }
        return urls
    }

    static let cannedSubQueriesEnvelope: String = """
    {"subQueries": ["sub query one", "sub query two", "sub query three"]}
    """

    static let cannedContradictionEnvelope: String = """
    {"pairs": []}
    """

    static let cannedEntitiesEnvelope: String = """
    {"entities": [
      {"name": "Ethereum", "kind": "project", "cluster": "c1"},
      {"name": "Vitalik Buterin", "kind": "person", "cluster": "c1"},
      {"name": "EigenLayer", "kind": "project", "cluster": "c2"}
    ]}
    """

    static let cannedCounterpointsEnvelope: String = """
    {"hits": [
      {"cluster": "c1", "counterpoint": "A skeptic would argue the synthetic items don't establish causation.", "gap": "Doesn't address counter-cyclical capital flow."},
      {"cluster": "c2", "counterpoint": null, "gap": "Doesn't address regulatory exposure."}
    ]}
    """

    static let cannedFollowUpsEnvelope: String = """
    {"suggestions": [
      {"name": "ETH staking deep-dive", "query": "ethereum staking validator economics", "sources": ["hackerNews", "reddit"]},
      {"name": "Restaking weekly", "query": "eigenlayer symbiotic restaking", "sources": ["news"]},
      {"name": "L2 readiness", "query": "L2 rollup pectra readiness", "sources": ["hackerNews", "rss"]}
    ]}
    """

    static let cannedSmartTitle: String = "Pectra lands May 22 as restaking TVL crosses 5.6M"

    func summarize(prompt: String, model: String?) async throws -> LLMResponse {
        // Heuristic routing: the rewriter, contradiction detector, entity
        // extractor, and briefing prompt are distinct enough that we can
        // pick the right canned response by sniffing the prompt.
        let text: String
        if prompt.contains("`subQueries`") {
            text = Self.cannedSubQueriesEnvelope
        } else if prompt.contains("disagreeing pairs") || prompt.contains("`pairs`") {
            text = Self.cannedContradictionEnvelope
        } else if prompt.contains("Extract a flat list of named entities") {
            text = Self.cannedEntitiesEnvelope
        } else if prompt.contains("critical-reading coach") {
            text = Self.cannedCounterpointsEnvelope
        } else if prompt.contains("follow-up topic presets") {
            text = Self.cannedFollowUpsEnvelope
        } else if prompt.contains("Write a single 6-12 word") {
            text = Self.cannedSmartTitle
        } else {
            // Briefing prompt: echo the prompt's own input URLs as citations
            // so CitationValidator keeps the clusters regardless of how the
            // caller namespaced its item URLs.
            text = Self.briefing(citingURLsFrom: prompt)
        }
        return LLMResponse(
            text: text,
            model: model ?? defaultModel,
            usage: LLMUsage(promptTokens: prompt.count / 4, completionTokens: text.count / 4)
        )
    }
}
#endif
