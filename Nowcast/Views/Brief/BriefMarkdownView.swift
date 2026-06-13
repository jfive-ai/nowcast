import SwiftUI

/// Renders brief markdown as styled blocks (headings, bullet/numbered lists,
/// blockquotes, thematic breaks, code, prose) instead of the previous flat
/// line-by-line text. Inline markdown (bold/italic/links) is preserved per
/// line, and any line carrying a `[label](url)` link keeps the hoverable
/// citation chip row (P6-1) via `BriefInlineText`.
struct BriefMarkdownView: View {
    let blocks: [BriefMarkdownBlock]
    let urlIndex: [String: PersistedItem]
    /// Extra spacing between body lines — tuned for readability (V11).
    var lineSpacing: CGFloat

    init(markdown: String,
         urlIndex: [String: PersistedItem] = [:],
         lineSpacing: CGFloat = 5) {
        self.blocks = BriefMarkdown.parse(markdown)
        self.urlIndex = urlIndex
        self.lineSpacing = lineSpacing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: BriefMarkdownBlock) -> some View {
        switch block {
        case let .heading(level, text):
            headingView(level: level, text: text)

        case let .paragraph(lines):
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    BriefInlineText(line: line, urlIndex: urlIndex, lineSpacing: lineSpacing)
                }
            }

        case let .bulletList(items):
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    listRow(marker: "•", item: item)
                }
            }

        case let .numberedList(items):
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    listRow(marker: "\(idx + 1).", item: item)
                }
            }

        case let .quote(lines):
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.accentColor.opacity(0.45))
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        BriefInlineText(line: line, urlIndex: urlIndex, lineSpacing: lineSpacing)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 2)

        case let .code(lines):
            Text(lines.joined(separator: "\n"))
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .padding(Theme.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                        .fill(Theme.Colors.cardFill)
                )

        case .thematicBreak:
            Rectangle()
                .fill(Theme.Colors.hairline)
                .frame(height: 1)
                .padding(.vertical, Theme.Spacing.xs)
        }
    }

    @ViewBuilder
    private func headingView(level: Int, text: String) -> some View {
        let font: Font = level == 1 ? .title.bold()
            : (level == 2 ? .title2.bold() : .title3.bold())
        VStack(alignment: .leading, spacing: 3) {
            Text(text).font(font)
            if level <= 2 {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.30))
                    .frame(width: 40, height: 2)
            }
        }
        .padding(.top, level == 1 ? Theme.Spacing.sm : Theme.Spacing.xs)
    }

    @ViewBuilder
    private func listRow(marker: String, item: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
            Text(marker)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(minWidth: 15, alignment: .trailing)
            BriefInlineText(line: item, urlIndex: urlIndex, lineSpacing: lineSpacing)
        }
    }
}

/// One inline-markdown line: bold/italic/links parsed via `AttributedString`,
/// plus a citation chip row under any line that contains a `[label](url)` link.
struct BriefInlineText: View {
    let line: String
    var urlIndex: [String: PersistedItem] = [:]
    var lineSpacing: CGFloat = 5

    var body: some View {
        if line.contains("](") {
            VStack(alignment: .leading, spacing: 2) {
                Text(attributed).lineSpacing(lineSpacing)
                CitationChipRow(markdown: line, urlIndex: urlIndex)
            }
        } else {
            Text(attributed).lineSpacing(lineSpacing)
        }
    }

    private var attributed: AttributedString {
        (try? AttributedString(
            markdown: line,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        )) ?? AttributedString(line)
    }
}

/// Renders the hoverable citation chips for a markdown line (P6-1). Pulls links
/// out of the line, looks each up in `urlIndex`, and shows a source-tinted chip
/// with a popover preview on hover.
struct CitationChipRow: View {
    let markdown: String
    let urlIndex: [String: PersistedItem]

    var body: some View {
        let pairs = MarkdownLinkText.split(markdown).compactMap(\.linkPair)
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                CitationChipButton(
                    label: pair.0,
                    url: pair.1,
                    item: urlIndex[MarkdownLinkText.normalize(pair.1)]
                )
            }
        }
    }
}

private struct CitationChipButton: View {
    let label: String
    let url: String
    let item: PersistedItem?
    @State private var isHovering = false

    var body: some View {
        Link(destination: URL(string: url) ?? URL(string: "about:blank")!) {
            // Shared design-system Chip so inline citations match the cluster
            // host chips (V6) exactly.
            Chip(host, systemImage: symbol, tint: tint)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .popover(isPresented: $isHovering, arrowEdge: .top) {
            CitationPopover(label: label, urlString: url, item: item)
        }
    }

    private var tint: Color {
        if let item { return SourcePalette.color(for: item.sourceKind) }
        return SourcePalette.unknownColor
    }

    private var symbol: String {
        if let item { return SourcePalette.symbol(for: item.sourceKind) }
        return SourcePalette.unknownSymbol
    }

    private var host: String {
        URL(string: url)?.host?.replacingOccurrences(of: "www.", with: "") ?? url
    }
}

#if DEBUG
#Preview("BriefMarkdownView") {
    ScrollView {
        BriefMarkdownView(markdown: """
        # Briefing
        ## TL;DR
        - First key point with **bold** emphasis
        - Second point linking out [example.com](https://example.com)

        ## Stories
        ### A story headline
        A short paragraph explaining the story in prose, with an *italic* aside.

        > A blockquote with a counterpoint worth weighing.

        1. Ordered item one
        2. Ordered item two

        ---

        `inline-ish` and a fenced block:
        ```
        let x = 1
        ```
        """)
        .padding()
    }
    .frame(width: 560, height: 620)
}
#endif
