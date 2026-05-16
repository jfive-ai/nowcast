import SwiftUI

/// Debounced full-text search across persisted reports. Hit rows highlight
/// the matching snippet using FTS5's `snippet()` markers and let the user
/// jump to the source report.
struct SearchView: View {
    @EnvironmentObject private var state: AppState
    @State private var query: String = ""
    @State private var hits: [StorageManager.SearchHit] = []
    @State private var debounceWork: DispatchWorkItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search reports…", text: $query)
                .textFieldStyle(.roundedBorder)
                .onChange(of: query) { _ in schedule() }
                .padding(.horizontal)
                .padding(.top, 8)

            if query.isEmpty {
                emptyHint
            } else if hits.isEmpty {
                noMatches
            } else {
                List(hits, selection: openReportBinding) { hit in
                    HitRow(hit: hit)
                        .tag(Optional(hit))
                }
                .listStyle(.inset)
            }
        }
    }

    private var emptyHint: some View {
        VStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.title)
                .foregroundStyle(.secondary)
            Text("Search across every report")
                .font(.headline)
            Text("Searches topic, body, and item titles. Tokens are stemmed.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noMatches: some View {
        VStack(spacing: 6) {
            Image(systemName: "questionmark.circle")
                .font(.title)
                .foregroundStyle(.secondary)
            Text("No matches")
                .font(.headline)
            Text("Try a shorter query, different keyword, or a topic name.")
                .font(.caption)
                .foregroundStyle(.secondary)
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

    private func schedule() {
        debounceWork?.cancel()
        let snapshot = query
        let work = DispatchWorkItem {
            hits = state.searchReports(snapshot)
        }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
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

    /// Convert `<<term>>…` FTS5 snippet output into AttributedString with
    /// the terms styled.
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
