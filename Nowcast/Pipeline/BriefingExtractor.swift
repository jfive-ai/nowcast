import Foundation

/// Extracts the trailing JSON block (`<!-- briefing-json --> \`\`\`json ... \`\`\``)
/// from an LLM response, plus the visible markdown that precedes it.
/// Tolerant — if no JSON block is present (older prompt, model misbehaved,
/// non-structured-aware provider), returns `markdown: response, result: nil`.
enum BriefingExtractor {
    struct Extracted {
        let markdown: String
        let result: BriefingResult?
    }

    static func extract(from response: String) -> Extracted {
        guard let (jsonString, markdownPrefix) = locateJSONBlock(in: response) else {
            return Extracted(markdown: response, result: nil)
        }

        do {
            let data = Data(jsonString.utf8)
            let decoded = try JSONDecoder().decode(BriefingResult.self, from: data)
            return Extracted(markdown: markdownPrefix, result: decoded)
        } catch {
            // Bad JSON — better to keep the visible markdown than crash.
            return Extracted(markdown: response, result: nil)
        }
    }

    /// Finds the last ```json ... ``` fence and (if it exists) returns the
    /// JSON body and the markdown content before the fence (with the
    /// `<!-- briefing-json -->` sentinel stripped if it directly precedes
    /// the fence).
    private static func locateJSONBlock(in response: String) -> (json: String, prefix: String)? {
        // Search for the last opening fence so models that emit auxiliary
        // JSON earlier in the response don't confuse us.
        guard let openRange = response.range(of: "```json", options: .backwards) else {
            return nil
        }
        let afterOpen = openRange.upperBound
        guard let closeRange = response.range(of: "```", range: afterOpen..<response.endIndex) else {
            return nil
        }
        let raw = response[afterOpen..<closeRange.lowerBound]
        let json = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Trim the prefix: drop the sentinel comment line if present.
        var prefix = String(response[response.startIndex..<openRange.lowerBound])
        let sentinel = "<!-- briefing-json -->"
        if let sRange = prefix.range(of: sentinel, options: .backwards) {
            prefix = String(prefix[prefix.startIndex..<sRange.lowerBound])
        }
        prefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        return (json, prefix)
    }
}
