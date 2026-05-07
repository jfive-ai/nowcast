import SwiftUI

struct ReportView: View {
    @EnvironmentObject private var state: AppState
    let report: Report

    @State private var markdown: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(report.topic)
                    .font(.largeTitle).bold()

                HStack(spacing: 6) {
                    Text(report.generatedAt, style: .date)
                    Text(report.generatedAt, style: .time)
                    Text("·")
                    Text(report.window.displayName)
                    Text("·")
                    Text("\(report.sourceCount) items")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let usage = usageSummary {
                    Text(usage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                renderedMarkdown
                    .textSelection(.enabled)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: report.id) {
            markdown = state.loadMarkdown(for: report)
        }
    }

    /// Compact "<provider> · <model> · 1.2k tok · ~$0.01" line. `nil` when
    /// nothing useful was recorded (Ollama with no usage block, pre-v3 reports).
    private var usageSummary: String? {
        var parts: [String] = []
        if let provider = report.providerUsed, !provider.isEmpty {
            parts.append(provider)
        }
        if let model = report.modelUsed, !model.isEmpty {
            parts.append(model)
        }
        if let total = report.totalTokens, total > 0 {
            parts.append("\(total) tok")
        }
        if let cost = report.usdCost, cost > 0 {
            parts.append(cost < 0.01 ? "~<$0.01" : String(format: "~$%.3f", cost))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var renderedMarkdown: some View {
        // AttributedString(markdown:) handles inline markdown but not full
        // block elements like headings on macOS. For MVP, render line-by-line:
        // headings get bold/larger, blank lines preserved, everything else
        // parses as inline markdown for links/emphasis.
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(markdown.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, line in
                MarkdownLineView(line: String(line))
            }
        }
    }
}

private struct MarkdownLineView: View {
    let line: String

    var body: some View {
        if line.hasPrefix("### ") {
            Text(stripped(prefix: "### "))
                .font(.title3).bold()
                .padding(.top, 4)
        } else if line.hasPrefix("## ") {
            Text(stripped(prefix: "## "))
                .font(.title2).bold()
                .padding(.top, 6)
        } else if line.hasPrefix("# ") {
            Text(stripped(prefix: "# "))
                .font(.title).bold()
                .padding(.top, 8)
        } else if line.isEmpty {
            Text(" ")
        } else {
            Text(attributed)
        }
    }

    private func stripped(prefix p: String) -> String {
        String(line.dropFirst(p.count))
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
