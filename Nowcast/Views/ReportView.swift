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
    @State private var followUps: [FollowUpSuggester.Suggestion] = []
    @State private var presetDraft: TopicPreset?
    @State private var sentimentTrendOpen: Bool = false

    var body: some View {
        HSplitView {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(report.displayTitle)
                        .font(.largeTitle).bold()

                    if state.isBigStory(report) {
                        bigStoryBanner
                    }

                    if report.sentiment != nil {
                        sentimentIndicator
                    }

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

                    if !followUps.isEmpty {
                        FollowUpStrip(suggestions: followUps) { sug in
                            presetDraft = TopicPreset(
                                name: sug.name,
                                query: sug.query,
                                sources: sug.sources
                            )
                        }
                    }

                    Divider()

                    BriefMarkdownView(markdown: markdown, urlIndex: urlIndex)
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
            // P6-4: kick off follow-up suggestions in the background; the
            // strip is hidden until results land.
            followUps = []
            let tldr = Self.extractTLDR(from: markdown)
            let headlines = clusters.map(\.headline)
            let targetReportID = report.id
            // FIX (codex review PR #70 P1): the previous stale-result
            // check compared `reportRef.id == report.id` where both
            // came from the same `.task(id:)` capture and were therefore
            // always equal. After navigating from report A to report B,
            // A's slow LLM response could land later and overwrite B's
            // followUps. We now compare the captured `targetReportID`
            // against the *live* selection in state — only assign when
            // they still match.
            Task { @MainActor in
                let sugs = await state.suggestFollowUps(
                    for: report,
                    tldr: tldr,
                    clusterHeadlines: headlines
                )
                if state.selectedReportID == targetReportID {
                    followUps = sugs
                }
            }
        }
        .sheet(item: $presetDraft) { draft in
            TopicPresetEditor(preset: draft) { saved in
                state.savePreset(saved)
            }
        }
        .sheet(isPresented: $sentimentTrendOpen) {
            SentimentTrendView(
                presetName: presetName(for: report) ?? report.topic,
                reports: state.reports.filter { $0.presetID == report.presetID }
            )
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { sentimentTrendOpen = false }
                }
            }
        }
        // FIX (codex review PR #55 P2): if session is nil because the
        // user had no LLM key at first task fire, re-attempt the bind
        // whenever the user opens the chat drawer OR when key/provider
        // state changes downstream. Cheap: bind() short-circuits when
        // a valid session already exists for this report.
        .onChange(of: chatOpen) { newValue in
            if newValue { chatHolder.bind(report: report, state: state) }
        }
        .onReceive(state.$openAIAPIKey) { _ in chatHolder.bind(report: report, state: state) }
        .onReceive(state.$anthropicAPIKey) { _ in chatHolder.bind(report: report, state: state) }
        .onReceive(state.$llmProvider) { _ in chatHolder.bind(report: report, state: state) }
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

    /// Pulls TL;DR bullet lines out of brief markdown — same shape that
    /// `WebhookDeliverer` extracts. Used by P6-4 to feed the follow-up
    /// suggester a compact summary of the current brief.
    static func extractTLDR(from markdown: String) -> [String] {
        var out: [String] = []
        var inTLDR = false
        for line in markdown.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("## tl;dr") || trimmed.lowercased().hasPrefix("## tldr") {
                inTLDR = true; continue
            }
            if inTLDR {
                if trimmed.hasPrefix("## ") { break }
                if trimmed.hasPrefix("- ") { out.append(String(trimmed.dropFirst(2))) }
            }
        }
        return out
    }

    /// Wraps a single optional `BriefChatSession` so the report view's `task`
    /// can rebuild it when the user navigates between reports without losing
    /// the published bindings the drawer subscribes to.
    @MainActor
    final class ChatSessionHolder: ObservableObject {
        @Published var session: BriefChatSession?
        func bind(report: Report, state: AppState) {
            // FIX (codex review PR #55 P2): only short-circuit when we
            // ALREADY have a valid session for this report. If session
            // is nil (e.g. user fixed their API key after first load),
            // retry the makeBriefChatSession call so the chat drawer
            // becomes usable without forcing the user to navigate away.
            if let existing = session, existing.report.id == report.id {
                return
            }
            session = state.makeBriefChatSession(for: report)
        }
    }

    // MARK: - Audio

    private func presetName(for report: Report) -> String? {
        guard let pid = report.presetID else { return nil }
        return state.presets.first(where: { $0.id == pid })?.name
    }

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

    private var sentimentIndicator: some View {
        let sentiment = report.sentiment ?? 0
        let pct = (sentiment + 1) / 2  // map -1..1 → 0..1
        let label: String = {
            if sentiment > 0.25 { return "Bullish" }
            if sentiment < -0.25 { return "Bearish" }
            return "Neutral"
        }()
        let color: Color = sentiment > 0.25 ? .green : (sentiment < -0.25 ? .red : .secondary)
        return HStack(spacing: 10) {
            Text("Coverage tone").font(.caption).foregroundStyle(.secondary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.gray.opacity(0.18)).frame(height: 4)
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                        .offset(x: max(0, min(geo.size.width - 8, geo.size.width * pct - 4)))
                }
            }
            .frame(height: 8)
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(color)
                .frame(width: 60, alignment: .leading)
            if report.presetID != nil {
                Button {
                    sentimentTrendOpen = true
                } label: {
                    Label("Trend", systemImage: "chart.line.uptrend.xyaxis")
                        .labelStyle(.iconOnly)
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Show sentiment trend for this preset")
            }
        }
        .help(report.sentimentRationale ?? label)
    }

    private var bigStoryBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "flame.fill")
                .foregroundStyle(Color.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Big story")
                    .font(.callout).bold()
                if let headline = report.bigStoryHeadline, !headline.isEmpty {
                    Text(headline)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    Text("Unusually high cross-source agreement")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.orange.opacity(0.30), lineWidth: 0.5)
                )
        )
    }

}

