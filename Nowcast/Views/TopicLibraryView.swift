import SwiftUI

struct TopicLibraryView: View {
    @EnvironmentObject private var state: AppState
    @State private var topic: String = ""
    @State private var window: TimeWindow = .today
    @State private var editingPreset: TopicPreset?
    @State private var creatingPreset: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            adHocSection

            Divider()

            presetsSection
        }
        .sheet(isPresented: $creatingPreset) {
            TopicPresetEditor(preset: nil) { saved in
                state.savePreset(saved)
            }
        }
        .sheet(item: $editingPreset) { preset in
            TopicPresetEditor(preset: preset) { saved in
                state.savePreset(saved)
            }
        }
    }

    private var adHocSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("New briefing")
                .font(.headline)

            TextField("Topic (e.g. ethereum)", text: $topic)
                .textFieldStyle(.roundedBorder)
                .onSubmit { runIfReady() }

            Picker("Window", selection: $window) {
                ForEach(TimeWindow.allCases) { w in
                    Text(w.displayName).tag(w)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Spacer()
                Button {
                    runIfReady()
                } label: {
                    if state.isGenerating {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Generate")
                    }
                }
                .disabled(topic.trimmingCharacters(in: .whitespaces).isEmpty || state.isGenerating)
                .keyboardShortcut(.return, modifiers: [.command])
            }

            Text("Source: Hacker News (more in Phase 2)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Presets")
                    .font(.headline)
                Spacer()
                Button {
                    creatingPreset = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("New preset")
            }

            if state.presets.isEmpty {
                Text("No presets yet. Create one to schedule recurring briefings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(state.presets) { preset in
                    PresetRow(
                        preset: preset,
                        onRun: { Task { await state.runPreset(id: preset.id) } },
                        onEdit: { editingPreset = preset },
                        onDelete: { state.deletePreset(preset) }
                    )
                }
            }
        }
    }

    private func runIfReady() {
        let trimmed = topic.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !state.isGenerating else { return }
        Task { await state.generate(topic: trimmed, window: window, sources: [.hackerNews]) }
    }
}

private struct PresetRow: View {
    let preset: TopicPreset
    let onRun: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(preset.name)
                    .font(.body)
                    .lineLimit(1)
                Spacer()
                Button(action: onRun) {
                    Image(systemName: "play.fill")
                }
                .buttonStyle(.borderless)
                .help("Run now")
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("Edit")
                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete")
            }
            HStack(spacing: 6) {
                Text(preset.cadence.displayName)
                Text("·")
                Text(preset.window.displayName)
                if let last = preset.lastRunAt {
                    Text("·")
                    Text("last run \(last, style: .relative) ago")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
