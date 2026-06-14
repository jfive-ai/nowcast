import SwiftUI
import AppKit

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
            if let pair = state.compareSelection {
                CompareReportsView(left: pair.left, right: pair.right)
                    .id(pair.id)
                    .toolbar {
                        ToolbarItem(placement: .navigation) {
                            Button {
                                state.compareSelection = nil
                            } label: {
                                Label("Close", systemImage: "xmark.circle")
                            }
                        }
                    }
            } else if let report = selectedReport {
                ReportView(report: report)
                    .id(report.id)
                    .onAppear { state.markRead(reportID: report.id) }
            } else if !state.isProviderConfigured {
                onboardingCard
            } else {
                placeholder
            }
        }
        .overlay(alignment: .topTrailing) {
            if let gen = state.generation {
                ProgressTimelineView(state: gen)
                    .padding(16)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.25), value: state.generation?.history.count)
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { state.lastError != nil },
                set: { if !$0 { state.lastError = nil } }
            )
        ) {
            Button("Open Settings") {
                state.lastError = nil
                Self.openSettings()
            }
            Button("OK", role: .cancel) { state.lastError = nil }
        } message: {
            Text(state.lastError ?? "")
        }
    }

    /// Open the Settings/Preferences window. The selector differs between
    /// macOS 13 (showPreferencesWindow:) and macOS 14+ (showSettingsWindow:).
    static func openSettings() {
        let selector: Selector
        if #available(macOS 14, *) {
            selector = Selector(("showSettingsWindow:"))
        } else {
            selector = Selector(("showPreferencesWindow:"))
        }
        NSApp.sendAction(selector, to: nil, from: nil)
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
        VStack(spacing: Theme.Spacing.lg) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 92, height: 92)
                Image(systemName: "newspaper")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            }
            VStack(spacing: Theme.Spacing.xs + 2) {
                Text("No briefing selected")
                    .font(.title3.bold())
                Text("Pick a topic above to generate a fresh briefing, or open one from your history on the left.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
            HStack(spacing: Theme.Spacing.xl) {
                hint(icon: "sparkles", text: "Generate")
                hint(icon: "clock.arrow.circlepath", text: "History")
                hint(icon: "magnifyingglass", text: "Search")
            }
            .padding(.top, Theme.Spacing.xs)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private var onboardingCard: some View {
        VStack(spacing: Theme.Spacing.lg) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 92, height: 92)
                Image(systemName: "key.horizontal")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            }
            VStack(spacing: Theme.Spacing.xs + 2) {
                Text("Welcome to Nowcast")
                    .font(.title3.bold())
                Text("To generate briefings, add an LLM provider key in Settings — Nowcast uses it to summarize what it collects from your sources. Your key is stored in the macOS Keychain.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }
            Button {
                Self.openSettings()
            } label: {
                Label("Open Settings", systemImage: "gearshape")
            }
            .buttonStyle(.borderedProminent)
            Text("or press ⌘,")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func hint(icon: String, text: String) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
