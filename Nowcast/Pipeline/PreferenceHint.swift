import Foundation

/// Builds the optional `# Avoid` block that gets injected into the briefing
/// prompt when the user has recently dismissed or thumbs-down'd clusters on
/// any topic. Mild signal: the model is asked to deprioritize, not exclude,
/// these themes — false positives shouldn't blow away real news.
enum PreferenceHint {
    static func build(from headlines: [String]) -> String? {
        // FIX (codex review PR #40): sanitize each headline before
        // interpolation. Headlines originate from prior LLM output and can
        // contain newlines, markdown control chars, or prompt-injection
        // payloads ("Ignore prior instructions and ..."). Collapse
        // whitespace, strip control characters, drop markdown sigils,
        // and clamp length so each headline stays inert bullet data.
        let sanitized = headlines
            .map { sanitize($0) }
            .filter { !$0.isEmpty }
        guard !sanitized.isEmpty else { return nil }
        let bullets = sanitized.prefix(10).map { "- \($0)" }.joined(separator: "\n")
        return """
        # Avoid (low priority — user previously dismissed)
        Treat the following themes/headlines as low priority unless they are central to the topic. Do not exclude entirely, but prefer other angles when possible:
        \(bullets)
        """
    }

    private static func sanitize(_ s: String) -> String {
        let mapped = String(s.unicodeScalars.map { scalar -> Character in
            if scalar.value == 0x0A || scalar.value == 0x0D || scalar.value == 0x09 {
                return " "
            }
            if scalar.properties.generalCategory == .control { return " " }
            return Character(scalar)
        })
        let stripped: Set<Character> = ["#", "*", "_", "`", "[", "]"]
        let withoutMd = String(mapped.filter { !stripped.contains($0) })
        let collapsed = withoutMd
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return String(collapsed.prefix(160))
    }
}
