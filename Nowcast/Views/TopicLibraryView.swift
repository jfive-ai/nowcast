import SwiftUI

struct TopicLibraryView: View {
    @EnvironmentObject private var state: AppState
    @State private var topic: String = ""
    @State private var window: TimeWindow = .today

    var body: some View {
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

    private func runIfReady() {
        let trimmed = topic.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !state.isGenerating else { return }
        Task { await state.generate(topic: trimmed, window: window, sources: [.hackerNews]) }
    }
}
