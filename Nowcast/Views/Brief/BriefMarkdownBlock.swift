import Foundation

/// A parsed block of brief markdown. `BriefMarkdownView` turns the LLM's
/// human-facing markdown into a sequence of these and styles each kind, so the
/// brief reads as structured content rather than raw text. Pure value type —
/// the parser (`BriefMarkdown.parse`) is deterministic and unit-testable.
enum BriefMarkdownBlock: Equatable {
    /// `#`/`##`/`###` headings (deeper levels clamp to 3).
    case heading(level: Int, text: String)
    /// A run of consecutive prose lines (each may carry inline markdown/links).
    case paragraph(lines: [String])
    /// `-`/`*`/`+`/`•` bullet list; each item is inline markdown.
    case bulletList(items: [String])
    /// `1.`/`1)` ordered list; each item is inline markdown.
    case numberedList(items: [String])
    /// `>` blockquote lines.
    case quote(lines: [String])
    /// Fenced ``` code block lines (rendered verbatim, monospaced).
    case code(lines: [String])
    /// `---` / `***` / `___` thematic break.
    case thematicBreak
}

enum BriefMarkdown {
    static func parse(_ markdown: String) -> [BriefMarkdownBlock] {
        var blocks: [BriefMarkdownBlock] = []
        var paragraph: [String] = []
        var bullets: [String] = []
        var numbers: [String] = []
        var quote: [String] = []
        var code: [String] = []
        var inCode = false

        func flushParagraph() {
            if !paragraph.isEmpty { blocks.append(.paragraph(lines: paragraph)); paragraph = [] }
        }
        func flushBullets() {
            if !bullets.isEmpty { blocks.append(.bulletList(items: bullets)); bullets = [] }
        }
        func flushNumbers() {
            if !numbers.isEmpty { blocks.append(.numberedList(items: numbers)); numbers = [] }
        }
        func flushQuote() {
            if !quote.isEmpty { blocks.append(.quote(lines: quote)); quote = [] }
        }
        func flushAll() { flushParagraph(); flushBullets(); flushNumbers(); flushQuote() }

        for rawLine in markdown.components(separatedBy: "\n") {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            // Fenced code toggling takes precedence over everything else.
            if trimmed.hasPrefix("```") {
                if inCode {
                    blocks.append(.code(lines: code)); code = []; inCode = false
                } else {
                    flushAll(); inCode = true
                }
                continue
            }
            if inCode { code.append(rawLine); continue }

            if trimmed.isEmpty { flushAll(); continue }

            if isThematicBreak(trimmed) {
                flushAll(); blocks.append(.thematicBreak); continue
            }

            if let (level, text) = heading(trimmed) {
                flushAll(); blocks.append(.heading(level: level, text: text)); continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph(); flushBullets(); flushNumbers()
                quote.append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
                continue
            }

            if let item = bulletItem(trimmed) {
                flushParagraph(); flushNumbers(); flushQuote()
                bullets.append(item); continue
            }

            if let item = numberedItem(trimmed) {
                flushParagraph(); flushBullets(); flushQuote()
                numbers.append(item); continue
            }

            // Plain prose line.
            flushBullets(); flushNumbers(); flushQuote()
            paragraph.append(trimmed)
        }

        if inCode && !code.isEmpty { blocks.append(.code(lines: code)) }
        flushAll()
        return blocks
    }

    // MARK: - Line classifiers (pure)

    static func isThematicBreak(_ s: String) -> Bool {
        let cleaned = s.replacingOccurrences(of: " ", with: "")
        guard cleaned.count >= 3 else { return false }
        return cleaned.allSatisfy { $0 == "-" }
            || cleaned.allSatisfy { $0 == "*" }
            || cleaned.allSatisfy { $0 == "_" }
    }

    static func heading(_ s: String) -> (level: Int, text: String)? {
        var level = 0
        for ch in s {
            if ch == "#" { level += 1 } else { break }
        }
        guard level >= 1, level <= 6 else { return nil }
        let rest = s.dropFirst(level)
        guard rest.first == " " else { return nil }   // require "# foo", not "#foo"
        return (min(level, 3), rest.trimmingCharacters(in: .whitespaces))
    }

    static func bulletItem(_ s: String) -> String? {
        for marker in ["- ", "* ", "+ ", "• "] where s.hasPrefix(marker) {
            return String(s.dropFirst(marker.count))
        }
        return nil
    }

    static func numberedItem(_ s: String) -> String? {
        var idx = s.startIndex
        var digits = 0
        while idx < s.endIndex, s[idx].isNumber {
            idx = s.index(after: idx); digits += 1
        }
        guard digits > 0, idx < s.endIndex else { return nil }
        let sep = s[idx]
        guard sep == "." || sep == ")" else { return nil }
        let afterSep = s.index(after: idx)
        guard afterSep < s.endIndex, s[afterSep] == " " else { return nil }
        return String(s[s.index(after: afterSep)...])
    }
}
