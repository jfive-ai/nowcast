import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ReportView: View {
    @EnvironmentObject private var state: AppState
    let report: Report

    @State private var markdown: String = ""
    @State private var copyFlash: Bool = false

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
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: copyMarkdown) {
                    Label(copyFlash ? "Copied" : "Copy", systemImage: "doc.on.doc")
                }
                .help("Copy the report markdown to the clipboard")

                Menu {
                    Button("Save as Markdown…") { saveMarkdown() }
                    Button("Save as PDF…") { savePDF() }
                    Divider()
                    Button("Share…") { share() }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(markdown.isEmpty)
            }
        }
    }

    // MARK: - Toolbar actions

    private func copyMarkdown() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(markdown, forType: .string)
        copyFlash = true
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            copyFlash = false
        }
    }

    private func saveMarkdown() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "\(ReportExporter.defaultBasename(for: report)).md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ReportExporter.writeMarkdown(markdown, to: url)
        } catch {
            state.lastError = error.localizedDescription
        }
    }

    private func savePDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(ReportExporter.defaultBasename(for: report)).pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ReportExporter.writePDF(markdown: markdown, to: url)
        } catch {
            state.lastError = error.localizedDescription
        }
    }

    private func share() {
        // Anchor the picker to the front window's content view so it
        // appears at the toolbar position rather than the screen origin.
        guard let window = NSApp.keyWindow ?? NSApp.windows.first,
              let anchor = window.contentView else { return }
        let picker = NSSharingServicePicker(items: [markdown])
        picker.show(relativeTo: .zero, of: anchor, preferredEdge: .minY)
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
