import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @State private var draftOpenAIKey: String = ""
    @State private var draftAnthropicKey: String = ""
    @State private var draftYouTubeKey: String = ""
    @State private var draftBraveKey: String = ""
    @State private var draftOpenAIModel: String = ""
    @State private var draftAnthropicModel: String = ""
    @State private var draftOllamaModel: String = ""
    @State private var draftOllamaURL: String = ""
    @State private var draftRetention: String = ""
    @State private var savedFlash: Bool = false
    @State private var selfCheckResult: String = ""
    @State private var selfCheckPassed: Bool? = nil
    @State private var selfCheckRunning: Bool = false

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            SubscriptionsView()
                .tabItem { Label("Sources", systemImage: "list.bullet.rectangle") }
            SourceHealthView()
                .tabItem { Label("Health", systemImage: "waveform.path.ecg") }
            AnalyticsView()
                .tabItem { Label("Analytics", systemImage: "chart.bar.xaxis") }
            NitterMirrorsView()
                .tabItem { Label("Nitter", systemImage: "network") }
            EmailSettingsView()
                .tabItem { Label("Email", systemImage: "envelope") }
        }
        .padding()
        .onAppear { loadDrafts() }
    }

    private func loadDrafts() {
        draftOpenAIKey = state.openAIAPIKey
        draftAnthropicKey = state.anthropicAPIKey
        draftYouTubeKey = state.youtubeAPIKey
        draftBraveKey = state.braveAPIKey
        draftOpenAIModel = state.openAIModel
        draftAnthropicModel = state.anthropicModel
        draftOllamaModel = state.ollamaModel
        draftOllamaURL = state.ollamaBaseURL
        draftRetention = String(state.retentionDays)
    }

    private var generalTab: some View {
        Form {
            Section("LLM provider") {
                Picker("Active provider", selection: providerBinding) {
                    ForEach(LLMProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.segmented)
                Text(providerHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            switch state.llmProvider {
            case .openAI: openAISection
            case .anthropic: anthropicSection
            case .ollama: ollamaSection
            }

            Section("YouTube Data API") {
                SecureField("API key", text: $draftYouTubeKey)
                    .textFieldStyle(.roundedBorder)
                Button("Save") {
                    state.saveYouTubeAPIKey(draftYouTubeKey)
                    flashSaved()
                }
                .disabled(draftYouTubeKey == state.youtubeAPIKey)
                Text("Required for YouTube search and channel adapters. Free tier: 10k quota / day.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Brave Search API") {
                SecureField("API key", text: $draftBraveKey)
                    .textFieldStyle(.roundedBorder)
                Button("Save") {
                    state.saveBraveAPIKey(draftBraveKey)
                    flashSaved()
                }
                .disabled(draftBraveKey == state.braveAPIKey)
                Text("Required for the Web search adapter.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Retention") {
                HStack {
                    TextField("Days", text: $draftRetention)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { commitRetention() }
                    Button("Apply") { commitRetention() }
                    Spacer()
                }
                Text("0 keeps reports forever.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Pipeline") {
                Toggle(isOn: queryRewritingBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Query rewriting")
                        Text("Fan out 3+ word topics into 2-4 sub-queries. One extra cheap LLM call per run; better recall.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: contradictionDetectionBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Contradiction detection")
                        Text("Second-pass scan for cross-source disagreement (numbers, dates, entities). One extra LLM call per brief.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: entityExtractionBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Entity extraction")
                        Text("Build a cross-brief entity index (people, orgs, projects, tickers). One cheap LLM call per run; falls back to a rule-based extractor offline.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: counterpointsBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Counterpoints (steel-man)")
                        Text("Per-cluster strongest counter-argument and \"what's not covered\" gap. One extra LLM call per brief; refuses to invent.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: smartTitlesBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Smart auto-titles")
                        Text("Auto-generate a one-line headline per brief. One small extra LLM call per run.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
#if DEBUG
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Button {
                            runSelfCheck()
                        } label: {
                            if selfCheckRunning {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("Run self-check")
                            }
                        }
                        .disabled(selfCheckRunning)
                        if let passed = selfCheckPassed {
                            Label(passed ? "PASS" : "FAIL", systemImage: passed ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                .foregroundStyle(passed ? .green : .red)
                                .font(.caption)
                        }
                    }
                    Text("Exercises every Phase-4 code path with a mock LLM. No API spend; inserts a small synthetic report.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !selfCheckResult.isEmpty {
                        ScrollView {
                            Text(selfCheckResult)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                        .frame(maxHeight: 180)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.secondary.opacity(0.08))
                        )
                    }
                }
#endif
            }

            Section("Storage") {
                HStack {
                    Text("Total report size")
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: state.totalReportBytes, countStyle: .file))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Reports stored")
                    Spacer()
                    Text("\(state.reports.count)")
                        .foregroundStyle(.secondary)
                }
                Button("Delete oldest 10") {
                    state.deleteOldest(10)
                }
                .disabled(state.reports.isEmpty)
                HStack {
                    Text("Items persisted")
                        .help("Number of unique source items the app has captured across all reports. Used for diff, search, and trust signals.")
                    Spacer()
                    Text("\(state.totalItemCount)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                HStack {
                    Text("Report ↔ item links")
                        .help("How many report→item edges exist in the database.")
                    Spacer()
                    Text("\(state.totalReportItemCount)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .formStyle(.grouped)
    }

#if DEBUG
    private func runSelfCheck() {
        selfCheckRunning = true
        selfCheckResult = "Running…"
        selfCheckPassed = nil
        Task { @MainActor in
            let result = await SelfCheck.run(storage: state.storage)
            selfCheckRunning = false
            selfCheckPassed = result.passed
            selfCheckResult = result.summary
            state.refresh()
        }
    }
#endif

    private var queryRewritingBinding: Binding<Bool> {
        Binding(
            get: { state.queryRewritingEnabled },
            set: { state.queryRewritingEnabled = $0 }
        )
    }

    private var contradictionDetectionBinding: Binding<Bool> {
        Binding(
            get: { state.contradictionDetectionEnabled },
            set: { state.contradictionDetectionEnabled = $0 }
        )
    }

    private var entityExtractionBinding: Binding<Bool> {
        Binding(
            get: { state.entityExtractionEnabled },
            set: { state.entityExtractionEnabled = $0 }
        )
    }

    private var counterpointsBinding: Binding<Bool> {
        Binding(
            get: { state.counterpointsEnabled },
            set: { state.counterpointsEnabled = $0 }
        )
    }

    private var smartTitlesBinding: Binding<Bool> {
        Binding(
            get: { state.smartTitlesEnabled },
            set: { state.smartTitlesEnabled = $0 }
        )
    }

    private var providerBinding: Binding<LLMProvider> {
        Binding(
            get: { state.llmProvider },
            set: { state.llmProvider = $0 }
        )
    }

    private var providerHint: String {
        switch state.llmProvider {
        case .openAI:
            return "Cloud — paid per token. Default model: \(LLMProvider.openAI.defaultModel)."
        case .anthropic:
            return "Cloud — paid per token. Default model: \(LLMProvider.anthropic.defaultModel)."
        case .ollama:
            return "Local — free, runs on this Mac. Requires Ollama running and the model pulled."
        }
    }

    private var openAISection: some View {
        Section("OpenAI") {
            SecureField("API key", text: $draftOpenAIKey)
                .textFieldStyle(.roundedBorder)
            TextField("Model (blank = \(LLMProvider.openAI.defaultModel))", text: $draftOpenAIModel)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Save") {
                    state.saveAPIKey(draftOpenAIKey)
                    state.openAIModel = draftOpenAIModel.trimmingCharacters(in: .whitespaces)
                    flashSaved()
                }
                .disabled(draftOpenAIKey == state.openAIAPIKey
                          && draftOpenAIModel == state.openAIModel)
                if savedFlash {
                    Text("Saved").foregroundStyle(.green).font(.caption)
                }
            }
        }
    }

    private var anthropicSection: some View {
        Section("Anthropic") {
            SecureField("API key", text: $draftAnthropicKey)
                .textFieldStyle(.roundedBorder)
            TextField("Model (blank = \(LLMProvider.anthropic.defaultModel))", text: $draftAnthropicModel)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Save") {
                    state.saveAnthropicAPIKey(draftAnthropicKey)
                    state.anthropicModel = draftAnthropicModel.trimmingCharacters(in: .whitespaces)
                    flashSaved()
                }
                .disabled(draftAnthropicKey == state.anthropicAPIKey
                          && draftAnthropicModel == state.anthropicModel)
                if savedFlash {
                    Text("Saved").foregroundStyle(.green).font(.caption)
                }
            }
            Text("Get a key from console.anthropic.com.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var ollamaSection: some View {
        Section("Ollama") {
            TextField("Base URL", text: $draftOllamaURL)
                .textFieldStyle(.roundedBorder)
            TextField("Model (blank = \(LLMProvider.ollama.defaultModel))", text: $draftOllamaModel)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Save") {
                    state.ollamaBaseURL = draftOllamaURL.trimmingCharacters(in: .whitespaces)
                    state.ollamaModel = draftOllamaModel.trimmingCharacters(in: .whitespaces)
                    flashSaved()
                }
                .disabled(draftOllamaURL == state.ollamaBaseURL
                          && draftOllamaModel == state.ollamaModel)
                if savedFlash {
                    Text("Saved").foregroundStyle(.green).font(.caption)
                }
            }
            Text("Default: \(AppState.defaultOllamaBaseURL). Make sure `ollama serve` is running and the model is pulled (`ollama pull <model>`).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func commitRetention() {
        if let v = Int(draftRetention.trimmingCharacters(in: .whitespaces)), v >= 0 {
            state.retentionDays = v
            state.applyRetention()
        }
    }

    private func flashSaved() {
        savedFlash = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            savedFlash = false
        }
    }
}
