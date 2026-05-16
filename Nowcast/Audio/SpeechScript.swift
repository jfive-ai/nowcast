import Foundation

/// Converts a briefing's markdown into a plain-text script tuned for TTS:
/// strips URLs, code fences, and the trailing structured-JSON footer;
/// expands tiny abbreviations; flattens markdown list bullets to spoken
/// pauses; keeps headings as standalone phrases so the synthesizer
/// produces natural section breaks.
enum SpeechScript {
    private static let abbreviations: [(String, String)] = [
        ("TL;DR", "Quick take"),
        ("e.g.", "for example"),
        ("i.e.", "that is"),
        ("vs.", "versus"),
        ("USD", "US dollars"),
        ("YoY", "year over year"),
        ("QoQ", "quarter over quarter"),
    ]

    static func make(from markdown: String) -> String {
        var text = markdown

        // Strip the trailing structured-JSON footer if present.
        if let r = text.range(of: "<!-- briefing-json -->") {
            text = String(text[..<r.lowerBound])
        }

        var lines: [String] = []
        var inCodeFence = false
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(rawLine)

            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inCodeFence.toggle()
                continue
            }
            if inCodeFence { continue }

            // Headings become standalone phrases with a period.
            if line.hasPrefix("# ") {
                line = String(line.dropFirst(2)) + "."
            } else if line.hasPrefix("## ") {
                line = String(line.dropFirst(3)) + "."
            } else if line.hasPrefix("### ") {
                line = String(line.dropFirst(4)) + "."
            }

            // Strip list bullet prefixes; bullets read better as sentences.
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                line = String(line.dropFirst(2))
            }

            // Drop URLs entirely — listening to "h-t-t-p-s-colon" is awful.
            line = stripLinks(line)

            // Expand tiny abbreviations.
            for (from, to) in abbreviations {
                line = line.replacingOccurrences(of: from, with: to)
            }

            // Collapse markdown emphasis markers.
            line = line.replacingOccurrences(of: "**", with: "")
            line = line.replacingOccurrences(of: "__", with: "")
            line = line.replacingOccurrences(of: "_", with: "")
            line = line.replacingOccurrences(of: "`", with: "")

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                lines.append(trimmed)
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Strip `[text](url)` and bare http(s) URLs, keeping the visible text
    /// of markdown links.
    private static func stripLinks(_ s: String) -> String {
        var out = s
        // Markdown link `[text](url)` → `text`
        if let regex = try? NSRegularExpression(pattern: #"\[([^\]]+)\]\([^)]+\)"#) {
            let range = NSRange(out.startIndex..., in: out)
            out = regex.stringByReplacingMatches(in: out, range: range, withTemplate: "$1")
        }
        // Bare URLs
        if let regex = try? NSRegularExpression(pattern: #"https?:\/\/\S+"#) {
            let range = NSRange(out.startIndex..., in: out)
            out = regex.stringByReplacingMatches(in: out, range: range, withTemplate: "")
        }
        return out
    }
}
