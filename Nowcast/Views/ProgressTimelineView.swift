import SwiftUI
import AppKit

/// Live stage-by-stage timeline overlaid while a report is being generated
///. Bound to `AppState.generation`.
struct ProgressTimelineView: View {
    let state: GenerationState
    /// Stop the in-flight generation. When nil, no Stop button is shown.
    var onCancel: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            timeline
            footer
        }
        .frame(width: 380)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 16)
        // prod-38: announce each new stage so VoiceOver users aren't left
        // staring at a silent, frequently-updating overlay.
        .onChange(of: state.history.count) { _ in
            guard let latest = latestStageText else { return }
            announce(latest)
        }
    }

    /// Post a VoiceOver announcement for the latest stage. Uses the modern
    /// SwiftUI API on macOS 14+ and the AppKit notification on macOS 13
    /// (the app's deployment target).
    private func announce(_ text: String) {
        if #available(macOS 14, *) {
            AccessibilityNotification.Announcement(text).post()
        } else {
            NSAccessibility.post(
                element: NSApp as Any,
                notification: .announcementRequested,
                userInfo: [.announcement: text]
            )
        }
    }

    /// The most-recent stage's label, used for both the header's
    /// accessibility value and live announcements.
    private var latestStageText: String? {
        (state.current ?? state.history.last?.stage)?.displayName
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 1) {
                Text("Generating brief")
                    .font(.subheadline).bold()
                Text(state.topic)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(elapsedString)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            if let onCancel {
                Button(role: .destructive, action: onCancel) {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(.borderless)
                .help("Stop generating")
                .accessibilityLabel("Stop generating")
            }
        }
        .padding(12)
        // prod-38: expose the live progress to VoiceOver. The header is a
        // container so the Stop button stays its own focusable element while
        // the status text/value carries the current stage.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Generating brief for \(state.topic)")
        .accessibilityValue(latestStageText ?? "")
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var timeline: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(state.history.enumerated()), id: \.element.id) { idx, event in
                    row(event: event, isLast: idx == state.history.count - 1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(maxHeight: 340)
    }

    @ViewBuilder
    private func row(event: GenerationState.Event, isLast: Bool) -> some View {
        let active = state.current == event.stage && !event.stage.isTerminal
        let failed = isFailedStage(event.stage)
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                Image(systemName: event.stage.symbol)
                    .font(.caption)
                    .foregroundStyle(failed ? Color.red : (active ? Color.accentColor : .secondary))
                    .symbolVariant(active ? .fill : .none)
                    .accessibilityHidden(true)
                if !isLast {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.30))
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.stage.displayName)
                    .font(.callout)
                    .foregroundStyle(failed ? .red : .primary)
                Text(event.at, style: .time)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var footer: some View {
        HStack {
            if let current = state.current {
                Text(current.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text("\(state.history.count) stage\(state.history.count == 1 ? "" : "s")")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06))
    }

    // MARK: - Helpers

    private var elapsedString: String {
        let secs = state.elapsed
        if secs < 60 { return String(format: "%.1fs", secs) }
        return String(format: "%dm %ds", Int(secs / 60), Int(secs.truncatingRemainder(dividingBy: 60)))
    }

    private func isFailedStage(_ stage: PipelineStage) -> Bool {
        if case .failed = stage { return true }
        return false
    }
}
