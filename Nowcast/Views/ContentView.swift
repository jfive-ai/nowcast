import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                TopicLibraryView()
                    .padding()
                Divider()
                Picker("", selection: $state.sidebarSelection) {
                    Text("History").tag(AppState.SidebarSection.history)
                    Text("Search").tag(AppState.SidebarSection.search)
                    Text("Entities").tag(AppState.SidebarSection.entities)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 6)
                switch state.sidebarSelection {
                case .history:
                    HistoryView(selectedReport: selectionBinding)
                case .search:
                    SearchView()
                case .entities:
                    EntitiesView(selectedReport: selectionBinding)
                }
            }
            .frame(minWidth: 280)
        } detail: {
            if let report = selectedReport {
                ReportView(report: report)
                    .id(report.id)
                    .onAppear { state.markRead(reportID: report.id) }
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

    private var selectedReport: Report? {
        guard let id = state.selectedReportID else { return nil }
        return state.reports.first { $0.id == id }
    }

    private var selectionBinding: Binding<Report?> {
        Binding(
            get: { selectedReport },
            set: { state.selectedReportID = $0?.id }
        )
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
