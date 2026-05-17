import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ReportView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var audio: AudioBriefPlayer
    let report: Report

    @State private var markdown: String = ""
    @State private var copyFlash: Bool = false
    @State private var clusters: [BriefingResult.Cluster] = []
    @State private var reportFeedbackKinds: Set<Feedback.Kind> = []
    @State private var clusterFeedbackKinds: [String: Set<Feedback.Kind>] = [:]
    @State private var chatOpen: Bool = false
    @StateObject private var chatHolder = ChatSessionHolder()
    @State private var urlIndex: [String: PersistedItem] = [:]
    @State private var provenanceOpen: Bool = false
    @State private var provenanceRows: [ProvenanceBuilder.ClusterRows] = []

    var body: some View {
        HSplitView {
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

                    if !clusters.isEmpty {
                        Divider().padding(.top, 8)
                        Text("Clusters")
                            .font(.headline)
                        ForEach(clusters) { cluster in
                            clusterRow(cluster)
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if chatOpen, let session = chatHolder.session {
                ChatDrawerView(session: session)
            }
            if provenanceOpen {
                ProvenanceView(rows: provenanceRows)
            }
        }
        .task(id: report.id) {
            markdown = state.loadMarkdown(for: report)
            clusters = state.clusters(forReport: report.id)
            reportFeedbackKinds = Set(state.feedback(target: .report, targetID: report.id.uuidString).map(\.kind))
            var byCluster: [String: Set<Feedback.Kind>] = [:]
            for c in clusters {
                byCluster[c.id] = Set(state.feedback(target: .cluster, targetID: c.id).map(\.kind))
            }
            clusterFeedbackKinds = byCluster
            chatHolder.bind(report: report, state: state)
            // P6-1: build a URL → PersistedItem map for citation hover popovers.
            let items = state.itemsForReport(report.id)
            urlIndex = MarkdownLinkText.buildIndex(items: items)
            // P6-2: build the provenance rows for the drawer.
            provenanceRows = ProvenanceBuilder.build(clusters: clusters, items: items)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                audioButton

                feedbackToggle(.thumbsUp)
                feedbackToggle(.thumbsDown)
                feedbackToggle(.hallucination)

                Button {
                    chatOpen.toggle()
                    if chatOpen { provenanceOpen = false }
                } label: {
                    Label("Chat", systemImage: "bubble.left.and.bubble.right")
                        .foregroundStyle(chatOpen ? Color.accentColor : .secondary)
                }
                .help("Ask follow-up questions about this brief")

                Button {
                    provenanceOpen.toggle()
                    if provenanceOpen { chatOpen = false }
                } label: {
                    Label("Provenance", systemImage: "checkmark.seal")
                        .foregroundStyle(provenanceOpen ? Color.accentColor : .secondary)
                }
                .help("Show which items support each claim")

                Menu {
                    if let prior = state.priorReport(for: report) {
                        Button("Compare with prior (\(prior.generatedAt.formatted(date: .abbreviated, time: .omitted)))") {
                            state.compareSelection = AppState.ComparePair(left: prior, right: report)
                        }
                        Divider()
                    }
                    ForEach(state.candidateReportsForCompare(report)) { other in
                        Button(other.generatedAt.formatted(date: .abbreviated, time: .shortened)) {
                            state.compareSelection = AppState.ComparePair(left: other, right: report)
                        }
                    }
                } label: {
                    Label("Compare", systemImage: "rectangle.lefthalf.inset.filled.arrow.left")
                }
                .help("Compare this brief with another on the same topic")
                .menuStyle(.borderlessButton)
                .disabled(state.candidateReportsForCompare(report).isEmpty)

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

    /// Wraps a single optional `BriefChatSession` so the report view's `task`
    /// can rebuild it when the user navigates between reports without losing
    /// the published bindings the drawer subscribes to.
    @MainActor
    final class ChatSessionHolder: ObservableObject {
        @Published var session: BriefChatSession?
        func bind(report: Report, state: AppState) {
            if let existing = session, existing.report.id == report.id { return }
            session = state.makeBriefChatSession(for: report)
        }
    }

    // MARK: - Audio

    @ViewBuilder
    private var audioButton: some View {
        let playing = audio.isPlaying(reportID: report.id)
        let paused = audio.isPaused(reportID: report.id)
        Button {
            if playing {
                audio.pause()
            } else if paused {
                audio.play(reportID: report.id, markdown: markdown)
            } else {
                audio.play(reportID: report.id, markdown: markdown)
            }
        } label: {
            Label(
                playing ? "Pause" : (paused ? "Resume" : "Play"),
                systemImage: playing ? "pause.fill" : (paused ? "play.fill" : "play")
            )
            .foregroundStyle(playing || paused ? Color.accentColor : .secondary)
        }
        .help("Listen to this brief")
        .disabled(markdown.isEmpty)
    }

    // MARK: - Feedback

    @ViewBuilder
    private func feedbackToggle(_ kind: Feedback.Kind) -> some View {
        let active = reportFeedbackKinds.contains(kind)
        Button {
            toggleReportFeedback(kind)
        } label: {
            Label(kind.displayName, systemImage: kind.symbol)
                .symbolVariant(active ? .fill : .none)
                .foregroundStyle(active ? color(for: kind) : .secondary)
        }
        .help(kind.displayName)
    }

    private func color(for kind: Feedback.Kind) -> Color {
        switch kind {
        case .thumbsUp:      return .green
        case .thumbsDown:    return .orange
        case .hallucination: return .red
        case .star:          return .yellow
        case .dismiss:       return .gray
        }
    }

    private func toggleReportFeedback(_ kind: Feedback.Kind) {
        let target = report.id.uuidString
        if reportFeedbackKinds.contains(kind) {
            state.removeFeedback(target: .report, targetID: target, kind: kind)
            reportFeedbackKinds.remove(kind)
        } else {
            state.addFeedback(target: .report, targetID: target, kind: kind)
            reportFeedbackKinds.insert(kind)
        }
    }

    private func toggleClusterFeedback(_ clusterID: String, _ kind: Feedback.Kind) {
        var set = clusterFeedbackKinds[clusterID] ?? []
        if set.contains(kind) {
            state.removeFeedback(target: .cluster, targetID: clusterID, kind: kind)
            set.remove(kind)
        } else {
            state.addFeedback(target: .cluster, targetID: clusterID, kind: kind)
            set.insert(kind)
        }
        clusterFeedbackKinds[clusterID] = set
    }

    @ViewBuilder
    private func clusterRow(_ cluster: BriefingResult.Cluster) -> some View {
        let kinds = clusterFeedbackKinds[cluster.id] ?? []
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(cluster.headline)
                    .font(.subheadline).bold()
                Spacer()
                clusterButton(cluster.id, kind: .star, active: kinds.contains(.star))
                clusterButton(cluster.id, kind: .thumbsUp, active: kinds.contains(.thumbsUp))
                clusterButton(cluster.id, kind: .thumbsDown, active: kinds.contains(.thumbsDown))
                clusterButton(cluster.id, kind: .dismiss, active: kinds.contains(.dismiss))
            }
            Text(cluster.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let cp = cluster.counterpoint {
                counterpointRow(symbol: "exclamationmark.triangle", color: .orange, label: "Counter", text: cp)
            }
            if let gap = cluster.gap {
                counterpointRow(symbol: "questionmark.circle", color: .blue, label: "Not covered", text: gap)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.06))
        )
    }

    @ViewBuilder
    private func counterpointRow(symbol: String, color: Color, label: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .font(.caption)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.caption2).bold().foregroundStyle(color)
                Text(text).font(.caption)
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.08)))
    }

    @ViewBuilder
    private func clusterButton(_ clusterID: String, kind: Feedback.Kind, active: Bool) -> some View {
        Button {
            toggleClusterFeedback(clusterID, kind)
        } label: {
            Image(systemName: kind.symbol)
                .symbolVariant(active ? .fill : .none)
                .foregroundStyle(active ? color(for: kind) : .secondary)
        }
        .buttonStyle(.plain)
        .help(kind.displayName)
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
                MarkdownLineView(line: String(line), urlIndex: urlIndex)
            }
        }
    }
}

private struct MarkdownLineView: View {
    let line: String
    let urlIndex: [String: PersistedItem]

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
        } else if line.contains("](") {
            // P6-1: prose with at least one [label](url) gets the hoverable
            // citation chips below the line; headings + plain text fall
            // through to the simpler renderer.
            VStack(alignment: .leading, spacing: 2) {
                Text(attributed)
                CitationChipRow(markdown: line, urlIndex: urlIndex)
            }
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

/// Renders the hoverable citation chips for a given markdown line (P6-1).
/// Pulls links out of the line, looks each up in `urlIndex`, and shows a
/// chip with a popover preview on hover.
private struct CitationChipRow: View {
    let markdown: String
    let urlIndex: [String: PersistedItem]

    var body: some View {
        let pairs = MarkdownLinkText.split(markdown).compactMap(\.linkPair)
        HStack(spacing: 4) {
            ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                CitationChipButton(label: pair.0, url: pair.1, item: urlIndex[MarkdownLinkText.normalize(pair.1)])
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
            HStack(spacing: 4) {
                Image(systemName: "link.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(host)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.secondary.opacity(0.10))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .popover(isPresented: $isHovering, arrowEdge: .top) {
            CitationPopover(label: label, urlString: url, item: item)
        }
    }

    private var host: String {
        URL(string: url)?.host?.replacingOccurrences(of: "www.", with: "") ?? url
    }
}

