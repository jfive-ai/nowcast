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
    /// False until the brief's markdown/clusters have loaded from disk; gates
    /// the skeleton placeholder so content doesn't pop in from blank (V9).
    @State private var loaded: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HSplitView {
            ScrollView {
                if loaded {
                VStack(alignment: .leading, spacing: 12) {
                    ReportHeaderView(report: report)

                    StatStrip(
                        storyCount: clusters.count,
                        itemCount: report.sourceCount,
                        readMinutes: ReadingTime.minutes(for: markdown)
                    )

                    if state.isBigStory(report) {
                        bigStoryBanner
                    }

                    if report.sentiment != nil {
                        sentimentIndicator
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

                    BriefBodyView(markdown: markdown, urlIndex: urlIndex)
                        .textSelection(.enabled)

                    if !clusters.isEmpty {
                        Divider().padding(.top, 8)
                        SectionHeader("Clusters", systemImage: "square.stack.3d.up.fill",
                                      accent: .secondary, tintTitle: false)
                        ForEach(Array(clusters.enumerated()), id: \.element.id) { idx, cluster in
                            ClusterCardView(
                                cluster: cluster,
                                rank: idx + 1,
                                feedbackKinds: clusterFeedbackKinds[cluster.id] ?? [],
                                urlIndex: urlIndex,
                                onToggle: { kind in toggleClusterFeedback(cluster.id, kind) }
                            )
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: Theme.Layout.readingMeasure, alignment: .leading)
                .frame(maxWidth: .infinity)
                .transition(.opacity)
                } else {
                    ReportSkeletonView()
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: loaded)

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
            // Build a URL → PersistedItem map for citation hover popovers.
            let items = state.itemsForReport(report.id)
            urlIndex = MarkdownLinkText.buildIndex(items: items)
            // Core content (markdown, clusters, citations) is ready — swap the
            // skeleton for the real layout. NB: keep this before the first
            // `await` below; the loads above are synchronous, so there's no
            // cancellation window that could leave the skeleton stuck.
            loaded = true
            // Build the provenance rows for the drawer.
            provenanceRows = ProvenanceBuilder.build(clusters: clusters, items: items)
            // Kick off follow-up suggestions in the background; the
            // strip is hidden until results land.
            followUps = []
            let tldr = Self.extractTLDR(from: markdown)
            let headlines = clusters.map(\.headline)
            let targetReportID = report.id
            // Compare the captured `targetReportID` against the *live*
            // selection before assigning: after navigating from report A
            // to report B, A's slow LLM response can land later and would
            // otherwise overwrite B's followUps.
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
        // If session is nil because the user had no LLM key at first task
        // fire, re-attempt the bind whenever the user opens the chat
        // drawer OR when key/provider state changes downstream. Cheap:
        // bind() short-circuits when a valid session already exists for
        // this report.
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
                    Label(copyFlash ? "Copied" : "Copy",
                          systemImage: copyFlash ? "checkmark" : "doc.on.doc")
                        .foregroundStyle(copyFlash ? Color.green : .secondary)
                }
                .help("Copy the report markdown to the clipboard")
                .animation(reduceMotion ? nil : Theme.Motion.quick, value: copyFlash)

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
    /// `WebhookDeliverer` extracts. Feeds the follow-up suggester a
    /// compact summary of the current brief.
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
            // Only short-circuit when we ALREADY have a valid session for
            // this report. If session is nil (e.g. user fixed their API
            // key after first load), retry the makeBriefChatSession call
            // so the chat drawer becomes usable without forcing the user
            // to navigate away.
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
                .foregroundStyle(active ? kind.tint : .secondary)
                // Spring the fill/tint change so toggling feels responsive,
                // without a persistent scale that would misalign toolbar items.
                .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.6), value: active)
        }
        .help(kind.displayName)
        .accessibilityLabel(kind.displayName)
        .accessibilityValue(active ? "on" : "off")
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

    private var sentimentIndicator: some View {
        SentimentGauge(
            sentiment: report.sentiment ?? 0,
            rationale: report.sentimentRationale,
            onTrend: report.presetID != nil ? { sentimentTrendOpen = true } : nil
        )
    }

    private var bigStoryBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "flame.fill")
                .foregroundStyle(Color.orange)
                .accessibilityHidden(true)
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

