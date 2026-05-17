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

    /// Canned response keyed by prompt prefix. `summarize` picks the best
    /// match; falls back to a generic brief.
    static let cannedBrief: String = """
    ## TL;DR
    - Mock cluster A captured.
    - Mock cluster B captured.
    - No-op signal section.

    ## Stories

    ### Mock cluster A
    A short summary of the first synthetic cluster. Numbers: $42 outflows.

    Sources:
    - [Item one](https://mock.example/one)

    ### Mock cluster B
    A short summary of the second synthetic cluster.

    Sources:
    - [Item two](https://mock.example/two)

    ## Signal
    Synthetic signal for self-check.

    ## Sources
    - Hacker News
      - [Item one](https://mock.example/one)
      - [Item two](https://mock.example/two)

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
            { "text": "Outflows totaled $42.", "citations": ["https://mock.example/one"] }
          ],
          "citations": ["https://mock.example/one"]
        },
        {
          "id": "c2",
          "headline": "Mock cluster B",
          "summary": "A short summary of the second synthetic cluster.",
          "claims": [
            { "text": "Pectra activation window confirmed.", "citations": ["https://mock.example/two"] }
          ],
          "citations": ["https://mock.example/two"]
        }
      ],
      "signal": "Synthetic signal for self-check.",
      "low_confidence": false
    }
    ```
    """

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
        } else {
            text = Self.cannedBrief
        }
        return LLMResponse(
            text: text,
            model: model ?? defaultModel,
            usage: LLMUsage(promptTokens: prompt.count / 4, completionTokens: text.count / 4)
        )
    }
}
#endif
