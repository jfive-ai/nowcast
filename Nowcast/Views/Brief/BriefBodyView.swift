import SwiftUI

/// Renders a brief's markdown as a stack of classified, themed sections instead
/// of one flat blob. The TL;DR is pulled to the top ("answer first") and given
/// a hero callout; "Sources disagree" / "What's new" get accent callouts; the
/// rest render as standard cards. Hosted by `ReportView`; the compare view (V12)
/// is expected to adopt it too.
struct BriefBodyView: View {
    let markdown: String
    var urlIndex: [String: PersistedItem] = [:]

    private var sections: [BriefSection] {
        let all = BriefSectionizer.sections(from: markdown)
        // "Answer first": surface the TL;DR before contextual deltas, keeping
        // every other section in its original relative order.
        return all.filter { $0.kind == .tldr } + all.filter { $0.kind != .tldr }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                BriefSectionView(section: section, urlIndex: urlIndex)
            }
        }
    }
}

/// One classified brief section with per-kind chrome.
struct BriefSectionView: View {
    let section: BriefSection
    var urlIndex: [String: PersistedItem] = [:]

    var body: some View {
        switch section.kind {
        case .preamble:
            BriefMarkdownView(markdown: section.body, urlIndex: urlIndex)
        default:
            Card(accent: section.kind.fill) {
                header
                BriefMarkdownView(markdown: section.body, urlIndex: urlIndex)
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        let isCallout = section.kind.fill != nil
        SectionHeader(
            section.title.isEmpty ? "Section" : section.title,
            systemImage: section.kind.icon,
            accent: section.kind.tint,
            // Callouts tint the title too; standard sections keep a neutral
            // title with just a colored glyph.
            tintTitle: isCallout
        )
    }
}

#if DEBUG
#Preview("BriefBodyView") {
    ScrollView {
        BriefBodyView(markdown: """
        ## ⚠ Sources disagree
        - Numeric: "IBIT outflow >$80M" vs "IBIT outflow <$50M"

        ## What's new since last brief
        - ETH ETF flows turned net positive

        ## TL;DR
        - ETH ETF redemptions hit a one-week record
        - Pectra hard-fork activation window confirmed
        - Liquid restaking TVL crossed $3.2B

        ## Stories
        ### ETH ETF redemption week
        Spot ETH ETFs saw a record one-week outflow led by IBIT and FBTC.

        ## Signal
        Momentum is cooling, but staking fundamentals keep improving.

        ## Sources
        - Hacker News: [example](https://example.com)
        """)
        .padding()
    }
    .frame(width: 580, height: 700)
}
#endif
