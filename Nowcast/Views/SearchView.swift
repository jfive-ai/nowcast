import SwiftUI

/// In-app search across persisted reports. Two modes:
///   - Keyword (FTS5, P4-6) — exact-token + porter-stemmed matches with
///     in-snippet highlighting.
///   - Semantic (NLEmbedding, P8-1) — cosine similarity over per-report
///     sentence embeddings. Finds briefs by *meaning* even when the user
///     can't recall the exact phrasing.
/// `@MainActor`-isolated so the debounced search `Task` (in `schedule()`)
/// inherits main isolation: the heavy DB/cosine work still runs off-main inside
/// `AppState.*Async`'s `Task.detached`, but the `@State` result assignments
/// resume on the main thread (prod-29 review fix).
@MainActor
struct SearchView: View {
    @EnvironmentObject private var state: AppState

    enum Mode: String, CaseIterable, Identifiable {
        case keyword
        case semantic
        var id: String { rawValue }
        var label: String {
            switch self {
            case .keyword:  return "Keyword"
            case .semantic: return "Semantic"
            }
        }
    }

    @State private var mode: Mode = .keyword
    @State private var query: String = ""
    @State private var hits: [StorageManager.SearchHit] = []
    @State private var semanticHits: [AppState.SemanticHit] = []
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases) { m in Text(m.label).tag(m) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)
            .onChange(of: mode) { _ in schedule() }

            TextField(placeholder, text: $query)
                .textFieldStyle(.roundedBorder)
                .onChange(of: query) { _ in schedule() }
                .padding(.horizontal)

            content
        }
    }

    private var placeholder: String {
        switch mode {
        case .keyword:  return "Search reports…"
        case .semantic: return "Find by meaning, not just keyword…"
        }
    }

    @ViewBuilder
    private var content: some View {
        if mode == .semantic, !state.semanticSearchAvailable {
            unavailableHint
        } else if query.isEmpty {
            emptyHint
        } else if mode == .keyword {
            if hits.isEmpty { noMatches } else {
                List(hits, selection: openReportBinding) { hit in
                    HitRow(hit: hit).tag(Optional(hit))
                }
                .listStyle(.inset)
            }
        } else {
            if semanticHits.isEmpty { noMatches } else {
                List(semanticHits, selection: openSemanticBinding) { hit in
                    SemanticHitRow(hit: hit).tag(Optional(hit))
                }
                .listStyle(.inset)
            }
        }
    }

    private var emptyHint: some View {
        VStack(spacing: 6) {
            Image(systemName: mode == .keyword ? "magnifyingglass" : "wand.and.stars")
                .font(.title)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(mode == .keyword
                 ? "Search across every report"
                 : "Find briefs by meaning")
                .font(.headline)
            Text(mode == .keyword
                 ? "Searches topic, body, and item titles. Tokens are stemmed."
                 : "Local on-device embeddings — no network, no API key.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var unavailableHint: some View {
        VStack(spacing: 6) {
            Image(systemName: "exclamationmark.bubble")
                .font(.title)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Semantic search unavailable")
                .font(.headline)
            Text("This macOS build didn't ship an English sentence model. Use Keyword instead.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noMatches: some View {
        VStack(spacing: 6) {
            Image(systemName: "questionmark.circle")
                .font(.title)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No matches")
                .font(.headline)
            Text(mode == .keyword
                 ? "Try a shorter query, different keyword, or a topic name."
                 : "Try a broader concept — semantic search rewards intent over exact words.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var openReportBinding: Binding<StorageManager.SearchHit?> {
        Binding(
            get: { nil },
            set: { hit in
                guard let hit else { return }
                state.selectedReportID = hit.reportID
                state.sidebarSelection = .history
            }
        )
    }

    private var openSemanticBinding: Binding<AppState.SemanticHit?> {
        Binding(
            get: { nil },
            set: { hit in
                guard let hit else { return }
                state.selectedReportID = hit.reportID
                state.sidebarSelection = .history
            }
        )
    }

    private func schedule() {
        searchTask?.cancel()
        let snapshot = query
        let currentMode = mode
        // prod-29: debounce, then run the actual search OFF the main thread so
        // the FTS query / cosine loop doesn't stutter typing on a large archive.
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            switch currentMode {
            case .keyword:
                let result = await state.searchReportsAsync(snapshot)
                guard !Task.isCancelled else { return }
                hits = result
                semanticHits = []
            case .semantic:
                let result = await state.semanticSearchAsync(snapshot)
                guard !Task.isCancelled else { return }
                semanticHits = result
                hits = []
            }
        }
    }
}

private struct HitRow: View {
    let hit: StorageManager.SearchHit

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(hit.topic)
                .font(.body).bold()
            Text(attributedSnippet)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(.vertical, 4)
    }

    private var attributedSnippet: AttributedString {
        var attr = AttributedString(hit.snippet)
        var scan = AttributedString()
        var remaining = Substring(hit.snippet)
        scan = AttributedString()
        while let openRange = remaining.range(of: "<<") {
            scan += AttributedString(remaining[..<openRange.lowerBound])
            remaining = remaining[openRange.upperBound...]
            if let closeRange = remaining.range(of: ">>") {
                var hl = AttributedString(remaining[..<closeRange.lowerBound])
                hl.foregroundColor = .accentColor
                hl.inlinePresentationIntent = .stronglyEmphasized
                scan += hl
                remaining = remaining[closeRange.upperBound...]
            } else {
                scan += AttributedString(remaining)
                remaining = Substring()
                break
            }
        }
        if !remaining.isEmpty {
            scan += AttributedString(remaining)
        }
        attr = scan
        return attr
    }
}

private struct SemanticHitRow: View {
    let hit: AppState.SemanticHit

    /// Cosine in [-1, +1] mapped to a 0–100% score. Negative cosines are
    /// pinned to 0 — they mean "actively unrelated," which the UI shouldn't
    /// dignify with a partial bar.
    private var displayScore: Double { max(0, min(1, hit.score)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(hit.displayTitle)
                    .font(.body).bold()
                Spacer()
                Text(Self.dateFormatter.string(from: hit.generatedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: displayScore)
                .progressViewStyle(.linear)
                .tint(.accentColor)
            Text(String(format: "Similarity %.0f%%", displayScore * 100))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
}
