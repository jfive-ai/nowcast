import Foundation

/// Prompt template ported from the `topic-pulse` skill: TL;DR → Stories →
/// Signal → Sources. Kept here so it's easy to iterate and test in isolation.
enum BriefingPrompt {
    static func render(topic: String,
                       window: TimeWindow,
                       items: [RawItem],
                       avoidHint: String? = nil) -> String {
        let dateString: String = {
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .short
            return f.string(from: Date())
        }()

        let serializedItems = items
            .enumerated()
            .map { Self.serialize(item: $1, index: $0 + 1) }
            .joined(separator: "\n\n")

        let avoidBlock = avoidHint.map { "\n\($0)\n" } ?? ""

        return """
        You are writing a short, opinionated briefing for a busy reader who wants to catch up on a topic without reading every link.
        \(avoidBlock)
        # Topic
        \(topic)

        # Window
        \(window.displayName) (as of \(dateString))

        # Inputs
        Below are \(items.count) items collected from the source(s). Each item has a title, url, snippet, and source. Use ONLY these inputs — do not invent facts, links, or quotes. If the inputs don't actually justify a claim, leave it out.

        \(serializedItems)

        # Output format

        Produce a single Markdown document, ~400–500 words, with these sections in this exact order:

        ## TL;DR
        Three punchy bullets. The reader should understand the headline takeaways from the bullets alone.

        ## Stories
        Cluster related items into 2–4 named stories. For each:
        - **Story headline** (one short line)
        - 2–3 sentence summary capturing what happened, why it matters, and any concrete numbers/dates from the inputs
        - A short list of source links (use Markdown link syntax with the original urls)

        ## Signal
        2–4 sentences with an opinionated take: trend shift, who's winning/losing, contrarian angle, what to watch next. Be specific, not generic. If the inputs are too thin for a real signal, say so plainly.

        ## Sources
        Group the source links by source type (e.g. "Hacker News", "YouTube", "Reddit") with bullet links. Every source listed must be used in a Story above.

        # Constraints
        - Be terse. No throat-clearing, no "in this briefing".
        - Don't repeat the topic name in headers.
        - If an input has a non-English title, summarize in English.
        - Do not include any meta-commentary about the prompt or your process.

        # Machine-readable footer (REQUIRED)
        After the Sources section, append the exact sentinel line `<!-- briefing-json -->` on its own line, then a fenced ```json``` block matching this shape (no trailing prose):

        ```json
        {
          "tldr": ["...", "...", "..."],
          "clusters": [
            {
              "id": "c1",
              "headline": "...",
              "summary": "...",
              "claims": [
                { "text": "...", "citations": ["https://..."] }
              ],
              "citations": ["https://...", "https://..."]
            }
          ],
          "signal": "...",
          "low_confidence": false
        }
        ```

        Rules for the JSON block:
        - Every URL in `citations` MUST appear in the inputs above. Do not invent URLs.
        - `clusters` must correspond 1-to-1 with the Stories section.
        - `low_confidence` is `true` only if the inputs are too thin to support a real signal.
        - The JSON must be valid (no trailing commas, no comments inside the block).
        """
    }

    private static func serialize(item: RawItem, index: Int) -> String {
        var lines: [String] = []
        lines.append("### Item \(index)")
        lines.append("- title: \(item.title)")
        lines.append("- url: \(item.url.absoluteString)")
        if let author = item.author { lines.append("- author: \(author)") }
        if let published = item.publishedAt {
            lines.append("- published: \(ISO8601DateFormatter().string(from: published))")
        }
        lines.append("- source: \(item.sourceKind.displayName)")
        if let snippet = item.snippet, !snippet.isEmpty {
            let trimmed = snippet
                .replacingOccurrences(of: "\n", with: " ")
                .prefix(800)
            lines.append("- snippet: \(trimmed)")
        }
        if let transcript = item.transcript, !transcript.isEmpty {
            let trimmed = transcript.prefix(2000)
            lines.append("- transcript_excerpt: \(trimmed)")
        }
        return lines.joined(separator: "\n")
    }
}
