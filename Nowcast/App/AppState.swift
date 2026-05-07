import Foundation
import Combine

/// App-wide observable state. Owns the storage handle, the current LLM
/// client, the pipeline, and the background scheduler. Rebuilds the LLM
/// client when the API key changes in Settings.
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var reports: [Report] = []
    @Published private(set) var presets: [TopicPreset] = []
    @Published private(set) var subscriptions: [SourceSubscription] = []
    @Published private(set) var totalReportBytes: Int64 = 0
    @Published private(set) var unreadCount: Int = 0
    @Published var lastError: String?
    @Published var isGenerating: Bool = false
    @Published var isSuggesting: Bool = false
    /// Bound by `ContentView` so external triggers (notifications, menu bar)
    /// can change which report is shown.
    @Published var selectedReportID: UUID?

    @Published var openAIAPIKey: String {
        didSet { rebuildPipeline() }
    }

    @Published var anthropicAPIKey: String {
        didSet { rebuildPipeline() }
    }

    @Published var youtubeAPIKey: String {
        didSet { rebuildPipeline() }
    }

    @Published var braveAPIKey: String {
        didSet { rebuildPipeline() }
    }

    @Published var smtpSettings: SMTPSettings {
        didSet { SMTPSettingsStore.shared.save(smtpSettings) }
    }

    /// Active LLM provider used by ReportPipeline + SourceSuggester.
    @Published var llmProvider: LLMProvider {
        didSet {
            UserDefaults.standard.set(llmProvider.rawValue, forKey: Self.llmProviderKey)
            rebuildPipeline()
        }
    }

    /// Per-provider model override. Empty means "use the provider default".
    @Published var openAIModel: String {
        didSet {
            UserDefaults.standard.set(openAIModel, forKey: Self.openAIModelKey)
            if llmProvider == .openAI { rebuildPipeline() }
        }
    }

    @Published var anthropicModel: String {
        didSet {
            UserDefaults.standard.set(anthropicModel, forKey: Self.anthropicModelKey)
            if llmProvider == .anthropic { rebuildPipeline() }
        }
    }

    @Published var ollamaModel: String {
        didSet {
            UserDefaults.standard.set(ollamaModel, forKey: Self.ollamaModelKey)
            if llmProvider == .ollama { rebuildPipeline() }
        }
    }

    @Published var ollamaBaseURL: String {
        didSet {
            UserDefaults.standard.set(ollamaBaseURL, forKey: Self.ollamaBaseURLKey)
            rebuildPipeline()
        }
    }

    /// Days to retain reports. 0 means keep forever.
    @Published var retentionDays: Int {
        didSet { UserDefaults.standard.set(retentionDays, forKey: Self.retentionDaysKey) }
    }

    let storage: StorageManager
    private let scheduler = BackgroundScheduler()

    private(set) var pipeline: ReportPipeline?

    static let retentionDaysKey = "nowcast.retention_days"
    static let defaultRetentionDays = 30
    static let llmProviderKey = "nowcast.llm.provider"
    static let openAIModelKey = "nowcast.llm.openai.model"
    static let anthropicModelKey = "nowcast.llm.anthropic.model"
    static let ollamaModelKey = "nowcast.llm.ollama.model"
    static let ollamaBaseURLKey = "nowcast.llm.ollama.base_url"
    static let defaultOllamaBaseURL = "http://localhost:11434"

    init() {
        // Storage MUST come up; if it doesn't, the app can't function.
        do {
            self.storage = try StorageManager()
        } catch {
            fatalError("Failed to open Nowcast database: \(error)")
        }

        self.openAIAPIKey = KeychainStore.shared.getSecret(account: KeychainAccount.openAI) ?? ""
        self.anthropicAPIKey = KeychainStore.shared.getSecret(account: KeychainAccount.anthropic) ?? ""
        self.youtubeAPIKey = KeychainStore.shared.getSecret(account: KeychainAccount.youtube) ?? ""
        self.braveAPIKey = KeychainStore.shared.getSecret(account: KeychainAccount.braveSearch) ?? ""
        self.smtpSettings = SMTPSettingsStore.shared.load()
        self.retentionDays = UserDefaults.standard.object(forKey: Self.retentionDaysKey) as? Int
            ?? Self.defaultRetentionDays

        let providerRaw = UserDefaults.standard.string(forKey: Self.llmProviderKey) ?? LLMProvider.openAI.rawValue
        self.llmProvider = LLMProvider(rawValue: providerRaw) ?? .openAI
        self.openAIModel = UserDefaults.standard.string(forKey: Self.openAIModelKey) ?? ""
        self.anthropicModel = UserDefaults.standard.string(forKey: Self.anthropicModelKey) ?? ""
        self.ollamaModel = UserDefaults.standard.string(forKey: Self.ollamaModelKey) ?? ""
        self.ollamaBaseURL = UserDefaults.standard.string(forKey: Self.ollamaBaseURLKey)
            ?? Self.defaultOllamaBaseURL

        rebuildPipeline()
        applyRetention()
        refresh()

        scheduler.onFire = { [weak self] presetID in
            await self?.runPreset(id: presetID)
        }
        scheduler.reschedule(presets)

        NotificationManager.shared.onTapReport = { [weak self] reportID in
            self?.selectedReportID = reportID
            self?.markRead(reportID: reportID)
        }
        Task { await NotificationManager.shared.requestAuthorization() }
    }

    // MARK: - Settings

    func saveAPIKey(_ key: String) {
        saveSecret(key, account: KeychainAccount.openAI) { self.openAIAPIKey = $0 }
    }

    func saveAnthropicAPIKey(_ key: String) {
        saveSecret(key, account: KeychainAccount.anthropic) { self.anthropicAPIKey = $0 }
    }

    func saveYouTubeAPIKey(_ key: String) {
        saveSecret(key, account: KeychainAccount.youtube) { self.youtubeAPIKey = $0 }
    }

    func saveBraveAPIKey(_ key: String) {
        saveSecret(key, account: KeychainAccount.braveSearch) { self.braveAPIKey = $0 }
    }

    func saveSMTPPassword(_ password: String) {
        saveSecret(password, account: KeychainAccount.smtpPassword) { _ in }
    }

    var hasSMTPPassword: Bool {
        !(KeychainStore.shared.getSecret(account: KeychainAccount.smtpPassword) ?? "").isEmpty
    }

    private func saveSecret(_ key: String, account: String, apply: (String) -> Void) {
        do {
            if key.isEmpty {
                try KeychainStore.shared.delete(account: account)
            } else {
                try KeychainStore.shared.setSecret(key, account: account)
            }
            apply(key)
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Reports

    func generate(topic: String, window: TimeWindow, sources: [SourceKind]) async {
        await runPipeline(topic: topic, window: window, sources: sources, presetID: nil)
    }

    func runPreset(id: UUID) async {
        guard let preset = presets.first(where: { $0.id == id }) else { return }
        await runPipeline(
            topic: preset.query,
            window: preset.window,
            sources: preset.sources,
            presetID: preset.id
        )
        try? storage.updatePresetLastRun(id: preset.id, at: Date())
        loadPresets()
    }

    private func runPipeline(topic: String,
                             window: TimeWindow,
                             sources: [SourceKind],
                             presetID: UUID?) async {
        guard let pipeline else {
            lastError = missingProviderMessage
            return
        }
        isGenerating = true
        defer { isGenerating = false }
        do {
            let report = try await pipeline.generate(
                topic: topic,
                window: window,
                sources: sources,
                presetID: presetID,
                subscriptions: subscriptions
            )
            refresh()

            if let presetID,
               let preset = presets.first(where: { $0.id == presetID }) {
                if preset.deliveryChannels.contains(.notification) {
                    await NotificationManager.shared.postReportReady(report)
                }
                if preset.deliveryChannels.contains(.email) {
                    await sendEmailDigest(report: report)
                }
                // .menuBar and .inApp surface implicitly via the menu bar
                // and history list; no extra side effect needed.
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refresh() {
        do {
            reports = try storage.listReports()
            totalReportBytes = try storage.totalReportBytes()
            unreadCount = try storage.unreadCount()
        } catch {
            lastError = error.localizedDescription
        }
        loadPresets()
        loadSubscriptions()
    }

    func deleteOldest(_ n: Int = 10) {
        do {
            try storage.deleteOldestReports(count: n)
            refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func applyRetention() {
        guard retentionDays > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(retentionDays) * 86_400)
        do {
            try storage.deleteReports(olderThan: cutoff)
            try storage.pruneSeenItems()
            refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func loadMarkdown(for report: Report) -> String {
        (try? storage.loadMarkdown(for: report)) ?? "_(could not load report file)_"
    }

    func markRead(reportID: UUID) {
        try? storage.markRead(reportID: reportID)
        refresh()
    }

    // MARK: - Presets

    func savePreset(_ preset: TopicPreset) {
        do {
            try storage.upsertPreset(preset)
            loadPresets()
            scheduler.reschedule(presets)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func deletePreset(_ preset: TopicPreset) {
        do {
            try storage.deletePreset(id: preset.id)
            loadPresets()
            scheduler.reschedule(presets)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func loadPresets() {
        do {
            presets = try storage.listPresets()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Subscriptions

    func saveSubscription(_ sub: SourceSubscription) {
        do {
            try storage.upsertSubscription(sub)
            loadSubscriptions()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func deleteSubscription(_ sub: SourceSubscription) {
        do {
            try storage.deleteSubscription(id: sub.id)
            loadSubscriptions()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func sendEmailDigest(report: Report) async {
        guard smtpSettings.isConfigured,
              let password = KeychainStore.shared.getSecret(account: KeychainAccount.smtpPassword),
              !password.isEmpty else {
            lastError = "SMTP not configured. Set host, credentials, and recipients in Settings → Email."
            return
        }
        let markdown = (try? storage.loadMarkdown(for: report)) ?? ""
        let sender = EmailDigestSender(settings: smtpSettings, password: password)
        do {
            try await sender.send(report: report, markdown: markdown)
        } catch {
            lastError = "Email digest failed: \(error.localizedDescription)"
        }
    }

    private func loadSubscriptions() {
        do {
            subscriptions = try storage.listSubscriptions()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// LLM-driven source discovery. Returns proposals; the caller decides
    /// which to actually persist (the user picks in the UI).
    func suggestSubscriptions(topic: String) async -> [SourceSubscription] {
        guard let llm = makeLLMClient() else {
            lastError = missingProviderMessage
            return []
        }
        isSuggesting = true
        defer { isSuggesting = false }
        let suggester = SourceSuggester(llm: llm)
        do {
            return try await suggester.suggest(topic: topic)
        } catch {
            lastError = error.localizedDescription
            return []
        }
    }

    // MARK: - Internals

    /// Build the active LLM client based on the user's provider selection.
    /// Returns nil when the selected provider lacks a required secret /
    /// configuration so callers can surface a helpful Settings prompt.
    private func makeLLMClient() -> LLMClient? {
        switch llmProvider {
        case .openAI:
            guard !openAIAPIKey.isEmpty else { return nil }
            return OpenAIClient(apiKey: openAIAPIKey)
        case .anthropic:
            guard !anthropicAPIKey.isEmpty else { return nil }
            return AnthropicClient(apiKey: anthropicAPIKey)
        case .ollama:
            let urlString = ollamaBaseURL.trimmingCharacters(in: .whitespaces)
            guard let url = URL(string: urlString.isEmpty ? Self.defaultOllamaBaseURL : urlString) else {
                return nil
            }
            return OllamaClient(baseURL: url)
        }
    }

    private var missingProviderMessage: String {
        switch llmProvider {
        case .openAI:    return "Set your OpenAI API key in Settings first."
        case .anthropic: return "Set your Anthropic API key in Settings first."
        case .ollama:    return "Configure the Ollama base URL in Settings first."
        }
    }

    private func rebuildPipeline() {
        guard let llm = makeLLMClient() else {
            pipeline = nil
            return
        }

        var adapters: [SourceAdapter] = [
            HackerNewsAdapter(),
            RedditAdapter(),
            RSSAdapter(),
            NewsAdapter(),
            NitterAdapter(mirrorStore: .shared),
        ]
        // YouTube + web search adapters only attach when the user has
        // supplied the corresponding API key — otherwise they would either
        // 401 or be useless.
        if !youtubeAPIKey.isEmpty {
            adapters.append(YouTubeSearchAdapter(apiKey: youtubeAPIKey))
            adapters.append(YouTubeChannelAdapter(apiKey: youtubeAPIKey))
        }
        if !braveAPIKey.isEmpty {
            adapters.append(BraveSearchAdapter(apiKey: braveAPIKey))
        }
        pipeline = ReportPipeline(
            adapters: adapters,
            storage: storage,
            llm: llm,
            model: activeModelOverride
        )
    }

    /// User-configured model override for the active provider, or nil to let
    /// the LLM client use its built-in default.
    private var activeModelOverride: String? {
        let raw: String
        switch llmProvider {
        case .openAI:    raw = openAIModel
        case .anthropic: raw = anthropicModel
        case .ollama:    raw = ollamaModel
        }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}
