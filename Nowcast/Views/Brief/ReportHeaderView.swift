import SwiftUI

/// The report's header: a topic glyph + title + kind/unread badges, with the
/// metadata (date, window, model, cost) rendered as wrapping pill chips instead
/// of a run-on gray caption.
struct ReportHeaderView: View {
    let report: Report

    private var tint: Color { TopicGlyph.tint(for: report.topic) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                glyph
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(report.displayTitle)
                        .font(.title).bold()
                        .fixedSize(horizontal: false, vertical: true)
                    badges
                }
                Spacer(minLength: 0)
            }
            FlowLayout {
                Chip(dateText, systemImage: "calendar")
                Chip(report.window.displayName, systemImage: "clock")
                if let model = modelText {
                    Chip(model, systemImage: "cpu")
                }
                if let cost = costText {
                    Chip(cost, systemImage: "dollarsign.circle")
                } else if let tokens = report.totalTokens, tokens > 0 {
                    Chip("\(tokens) tok", systemImage: "number")
                }
            }
        }
    }

    private var glyph: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            .fill(tint.opacity(0.16))
            .frame(width: 44, height: 44)
            .overlay(
                Image(systemName: TopicGlyph.symbol(for: report.topic))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
            )
    }

    @ViewBuilder
    private var badges: some View {
        HStack(spacing: Theme.Spacing.xs) {
            if report.kind == .weeklyDigest {
                Chip("Weekly digest", systemImage: "calendar.badge.clock", tint: .purple)
            }
            if report.isUnread {
                Chip("New", systemImage: "circle.fill", tint: .accentColor)
            }
        }
    }

    private var dateText: String {
        report.generatedAt.formatted(date: .abbreviated, time: .shortened)
    }

    private var modelText: String? {
        if let model = report.modelUsed, !model.isEmpty { return model }
        if let provider = report.providerUsed, !provider.isEmpty { return provider }
        return nil
    }

    private var costText: String? {
        guard let cost = report.usdCost, cost > 0 else { return nil }
        return cost < 0.01 ? "<$0.01" : String(format: "$%.3f", cost)
    }
}
