import SwiftUI
import AppKit

/// Compact content shown when the user clicks the menu-bar item.
/// Lists recent reports, exposes "Run now" per preset, and lets the user
/// open the main window.
struct MenuBarContentView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            recentReportsSection
            Divider()
            runNowSection
            Divider()
            footer
        }
        .frame(width: 320)
    }

    private var header: some View {
        HStack {
            Text("Nowcast")
                .font(.headline)
            Spacer()
            if state.unreadCount > 0 {
                Text("\(state.unreadCount) unread")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var recentReportsSection: some View {
        let recents = Array(state.reports.prefix(5))
        return VStack(alignment: .leading, spacing: 4) {
            Text("Recent")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            if recents.isEmpty {
                Text("No reports yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            } else {
                ForEach(recents, id: \.id) { report in
                    Button {
                        openReport(report)
                    } label: {
                        HStack(spacing: 6) {
                            if report.isUnread {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 6, height: 6)
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(report.topic)
                                    .lineLimit(1)
                                Text(report.generatedAt, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var runNowSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Run preset")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            if state.presets.isEmpty {
                Text("No presets configured.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            } else {
                ForEach(state.presets) { preset in
                    Button {
                        Task { await state.runPreset(id: preset.id) }
                    } label: {
                        HStack {
                            Image(systemName: "play.fill")
                                .foregroundStyle(.secondary)
                            Text(preset.name)
                                .lineLimit(1)
                            Spacer()
                            Text(preset.cadence.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .disabled(state.isGenerating)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Open Nowcast") {
                openMainWindow()
            }
            Spacer()
            Button("Quit") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: [.command])
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func openReport(_ report: Report) {
        state.markRead(reportID: report.id)
        state.selectedReportID = report.id
        openMainWindow()
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
            return
        }
    }
}
