import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var state: AppState
    @State private var selectedReport: Report?

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                TopicLibraryView()
                    .padding()
                Divider()
                HistoryView(selectedReport: $selectedReport)
            }
            .frame(minWidth: 280)
        } detail: {
            if let report = selectedReport {
                ReportView(report: report)
            } else {
                placeholder
            }
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { state.lastError != nil },
                set: { if !$0 { state.lastError = nil } }
            )
        ) {
            Button("OK") { state.lastError = nil }
        } message: {
            Text(state.lastError ?? "")
        }
    }

    private var placeholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Generate a briefing or pick one from history.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
