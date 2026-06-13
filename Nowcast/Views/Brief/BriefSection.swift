import SwiftUI

/// A titled `## section` of a brief, classified so the renderer can give the
/// high-value ones (TL;DR, "Sources disagree", "What's new") bespoke chrome
/// while everything else falls back to a standard card. Pure value type;
/// `BriefSectionizer.sections` is deterministic and unit-testable.
struct BriefSection: Equatable {
    enum Kind: Equatable {
        /// Content before the first `##` header — rendered plainly, no card.
        case preamble
        case tldr
        /// "Sources disagree" / "Counterpoints" — a contrast/warning callout.
        case contrast
        /// "What's new since last brief" / "What changed this week".
        case whatsNew
        case stories
        case signal
        case sources
        /// "To watch".
        case watch
        case generic

        var icon: String? {
            switch self {
            case .preamble, .generic: return nil
            case .tldr:     return "bolt.fill"
            case .contrast: return "exclamationmark.triangle.fill"
            case .whatsNew: return "clock.arrow.circlepath"
            case .stories:  return "newspaper.fill"
            case .signal:   return "antenna.radiowaves.left.and.right"
            case .sources:  return "link"
            case .watch:    return "eye.fill"
            }
        }

        /// Color for the leading glyph (and, for callouts, the title + fill).
        var tint: Color {
            switch self {
            case .tldr:     return .accentColor
            case .contrast: return .orange
            case .whatsNew: return .teal
            case .signal:   return .purple
            case .watch:    return .blue
            case .stories, .sources, .generic, .preamble: return .secondary
            }
        }

        /// Non-nil tints the whole card (callouts). `nil` → standard surface.
        var fill: Color? {
            switch self {
            case .tldr:     return .accentColor
            case .contrast: return .orange
            case .whatsNew: return .teal
            default:        return nil
            }
        }
    }

    let kind: Kind
    /// Header text with any leading emoji/symbol stripped (e.g. "⚠ Sources
    /// disagree" → "Sources disagree"). Empty for `.preamble`.
    let title: String
    /// The section's markdown body (header line excluded).
    let body: String
}

enum BriefSectionizer {
    /// Splits brief markdown into `## ` sections. Content before the first
    /// header becomes a `.preamble` section. `###` and deeper headings stay
    /// inside their section body.
    static func sections(from markdown: String) -> [BriefSection] {
        var sections: [BriefSection] = []
        var preamble: [String] = []
        var currentTitle: String?
        var currentBody: [String] = []
        var sawHeader = false

        func flush() {
            guard let title = currentTitle else { return }
            let body = currentBody.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            sections.append(BriefSection(kind: classify(title), title: cleanTitle(title), body: body))
            currentTitle = nil
            currentBody = []
        }

        for line in markdown.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("## ") {
                if sawHeader {
                    flush()
                } else {
                    let pre = preamble.joined(separator: "\n")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !pre.isEmpty {
                        sections.append(BriefSection(kind: .preamble, title: "", body: pre))
                    }
                    sawHeader = true
                }
                currentTitle = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else if sawHeader {
                currentBody.append(line)
            } else {
                preamble.append(line)
            }
        }
        flush()

        // No headers at all → the whole document is one preamble.
        if !sawHeader {
            let pre = preamble.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !pre.isEmpty {
                sections.append(BriefSection(kind: .preamble, title: "", body: pre))
            }
        }
        return sections
    }

    static func classify(_ rawTitle: String) -> BriefSection.Kind {
        let t = rawTitle.lowercased()
        if t.contains("tl;dr") || t.contains("tldr") { return .tldr }
        if t.contains("disagree") || t.contains("counterpoint") { return .contrast }
        if t.contains("what's new") || t.contains("whats new") || t.contains("what changed") { return .whatsNew }
        if t.contains("to watch") { return .watch }
        if t.contains("storyline") || t.contains("stories") { return .stories }
        if t.hasPrefix("signal") { return .signal }
        if t.contains("source") { return .sources }   // after the "disagree" check
        return .generic
    }

    /// Strip a leading emoji/symbol run so we can pair the title with our own
    /// glyph (e.g. "⚠ Sources disagree" → "Sources disagree").
    static func cleanTitle(_ raw: String) -> String {
        let cleaned = raw.drop(while: { !$0.isLetter && !$0.isNumber })
        let result = String(cleaned).trimmingCharacters(in: .whitespaces)
        return result.isEmpty ? raw : result
    }
}
