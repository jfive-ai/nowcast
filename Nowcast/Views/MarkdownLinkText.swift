import Foundation

/// Utility namespace for splitting a markdown line into prose + link
/// segments (P6-1). Consumed by `BriefInlineText` / `CitationChipRow` to render
/// citation chips with hover popovers under each line.
enum MarkdownLinkText {
    enum Segment {
        case plain(String)
        case link(label: String, url: String)

        var linkPair: (String, String)? {
            if case .link(let l, let u) = self { return (l, u) }
            return nil
        }
    }

    /// Splits a markdown string on `[label](url)` matches. Non-greedy.
    static func split(_ markdown: String) -> [Segment] {
        var out: [Segment] = []
        let pattern = #"\[([^\]]+)\]\(([^)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [.plain(markdown)]
        }
        let ns = markdown as NSString
        var cursor = 0
        let matches = regex.matches(in: markdown, range: NSRange(location: 0, length: ns.length))
        for m in matches where m.numberOfRanges == 3 {
            if m.range.location > cursor {
                let before = ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
                if !before.isEmpty { out.append(.plain(before)) }
            }
            let label = ns.substring(with: m.range(at: 1))
            let url = ns.substring(with: m.range(at: 2))
            out.append(.link(label: label, url: url))
            cursor = m.range.location + m.range.length
        }
        if cursor < ns.length {
            let tail = ns.substring(with: NSRange(location: cursor, length: ns.length - cursor))
            if !tail.isEmpty { out.append(.plain(tail)) }
        }
        if out.isEmpty { out.append(.plain(markdown)) }
        return out
    }

    /// Build a `{normalizedURL: PersistedItem}` index from a brief's items.
    static func buildIndex(items: [PersistedItem]) -> [String: PersistedItem] {
        var index: [String: PersistedItem] = [:]
        for item in items {
            index[normalize(item.canonicalURL.absoluteString)] = item
        }
        return index
    }

    /// Normalize so chip lookup matches what `URLCanonicalizer.hash` saw
    /// when the item was persisted. We use the same canonicalization
    /// pipeline so chips for `www.` / utm_*-bearing / fragment-bearing
    /// citation variants still resolve.
    ///
    /// FIX (codex review PRs #67/#68 P2): the previous "drop trailing
    /// slash + lowercase" was much weaker than `URLCanonicalizer`'s
    /// host-prefix / tracker-param / fragment stripping. Any citation
    /// that passed validation upstream could miss this lookup and the
    /// hover popover would falsely report "not in source set".
    static func normalize(_ urlString: String) -> String {
        guard let url = URL(string: urlString) else { return urlString.lowercased() }
        return URLCanonicalizer.canonicalize(url).absoluteString
    }
}
