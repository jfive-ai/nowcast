import Foundation

/// Helpers for pulling JSON out of free-form LLM responses, consolidating four
/// near-identical copy-pasted implementations (QueryRewriter, Contradiction
/// Detector, SourceSuggester, plus the brace-slice in CounterpointAgent /
/// EntityExtractor / FollowUpSuggester). One tested place to fix when a model
/// wraps its output in a new way (prod-24).
enum LLMJSON {
    /// Best-effort slice of the first JSON object embedded in free-form text —
    /// from the first `{` to the last `}`. Returns nil if there's no object.
    /// Tolerates a surrounding code fence (the braces sit inside it).
    static func firstJSONSlice(in raw: String) -> String? {
        guard let start = raw.firstIndex(of: "{"),
              let end = raw.lastIndex(of: "}"),
              start <= end else { return nil }
        return String(raw[start...end])
    }

    /// Strip a single ```…``` markdown code fence (and an optional `json`/`JSON`
    /// language tag) from `raw`, returning the inner content. If there's no
    /// fence, returns `raw` unchanged. Does not trim — callers trim as needed.
    static func stripFence(_ raw: String) -> String {
        guard let open = raw.range(of: "```") else { return raw }
        var body = String(raw[open.upperBound...])
        if body.lowercased().hasPrefix("json") { body = String(body.dropFirst(4)) }
        if let close = body.range(of: "```") { body = String(body[..<close.lowerBound]) }
        return body
    }
}
