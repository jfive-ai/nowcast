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
    @Published private(set) var totalItemCount: Int = 0
    @Published private(set) var totalReportItemCount: Int = 0
    @Published private(set) var unreadCount: Int = 0
    @Published var lastError: String?
    @Published var isGenerating: Bool = false
    /// Live state of the in-flight generation (P5-5). `nil` when idle.
    @Published var generation: GenerationState? = nil
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

    /// Fan-out the user's topic into 2-4 sub-queries before fetching.
    /// Costs one extra (cheap) LLM call per run. P4-9.
    @Published var queryRewritingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(queryRewritingEnabled, forKey: Self.queryRewritingKey)
            rebuildPipeline()
        }
    }

    /// Second-pass LLM scan over the brief's claims for cross-source
    /// disagreement. Costs one extra LLM call. P4-10.
    @Published var contradictionDetectionEnabled: Bool {
        didSet {
            UserDefaults.standard.set(contradictionDetectionEnabled, forKey: Self.contradictionDetectionKey)
            rebuildPipeline()
        }
    }

    /// Cross-brief entity extraction. One cheap LLM call per run, plus
    /// rule-based fallback. P5-2.
    @Published var entityExtractionEnabled: Bool {
        didSet {
            UserDefaults.standard.set(entityExtractionEnabled, forKey: Self.entityExtractionKey)
            rebuildPipeline()
        }
    }

    /// Steel-man counter-argument + "what's not covered" pass. One extra
    /// LLM call per brief. P5-3.
    @Published var counterpointsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(counterpointsEnabled, forKey: Self.counterpointsKey)
            rebuildPipeline()
        }
    }

    let storage: StorageManager
    private let scheduler = BackgroundScheduler()

    private(set) var pipeline: ReportPipeline?

    static let retentionDaysKey = "nowcast.retention_days"
    static let queryRewritingKey = "nowcast.query_rewriting_enabled"
    static let contradictionDetectionKey = "nowcast.contradiction_detection_enabled"
    static let entityExtractionKey = "nowcast.entity_extraction_enabled"
    static let counterpointsKey = "nowcast.counterpoints_enabled"
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
        self.queryRewritingEnabled = UserDefaults.standard.object(forKey: Self.queryRewritingKey) as? Bool ?? false
        self.contradictionDetectionEnabled = UserDefaults.standard.object(forKey: Self.contradictionDetectionKey) as? Bool ?? false
        self.entityExtractionEnabled = UserDefaults.standard.object(forKey: Self.entityExtractionKey) as? Bool ?? false
        self.counterpointsEnabled = UserDefaults.standard.object(forKey: Self.counterpointsKey) as? Bool ?? false

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

        // Rebuild the Spotlight index from the current report set so it
        // matches reality even if the user pruned reports while the app
        // was closed or installed a fresh build.
        SpotlightIndexer.shared.reindex(reports: reports) { [weak self] report in
            (try? self?.storage.loadMarkdown(for: report)) ?? ""
        }

        // P5-6: at launch, fire any due weekly digests for opt-in presets.
        Task { [weak self] in
            await self?.runDueWeeklyDigests()
        }
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
        generation = GenerationState(topic: topic, startedAt: Date())
        defer {
            isGenerating = false
            // Keep the final state visible for a moment so the user can
            // see the "Done" stage land before the overlay dismisses.
            let toClear = generation
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                if self.generation == toClear { self.generation = nil }
            }
        }
        do {
            let report = try await pipeline.generate(
                topic: topic,
                window: window,
                sources: sources,
                presetID: presetID,
                subscriptions: subscriptions,
                progress: { [weak self] stage in
                    Task { @MainActor [weak self] in
                        self?.generation?.push(stage)
                    }
                }
            )
            refresh()

            // Spotlight donation: searchable from anywhere on the Mac.
            let markdown = (try? storage.loadMarkdown(for: report)) ?? ""
            SpotlightIndexer.shared.donate(report: report, markdown: markdown)

            if let presetID,
               let preset = presets.first(where: { $0.id == presetID }) {
                if preset.deliveryChannels.contains(.notification) {
                    await NotificationManager.shared.postReportReady(report)
                }
                if preset.deliveryChannels.contains(.email) {
                    await sendEmailDigest(report: report)
                }
                // P5-4: webhook delivery. Each preset can have N webhook
                // channels; each one POSTs independently. Failures land
                // in `lastError` but never block the report from saving.
                for channel in preset.deliveryChannels {
                    guard let cfg = channel.webhookConfig, !cfg.url.isEmpty else { continue }
                    await deliverWebhook(report: report, config: cfg)
                }
                // .menuBar and .inApp surface implicitly via the menu bar
                // and history list; no extra side effect needed.
            }
        } catch {
            lastError = error.localizedDescription
            generation?.push(.failed(message: error.localizedDescription))
        }
    }

    func refresh() {
        do {
            reports = try storage.listReports()
            totalReportBytes = try storage.totalReportBytes()
            unreadCount = try storage.unreadCount()
            totalItemCount = (try? storage.totalItemCount()) ?? 0
            totalReportItemCount = (try? storage.totalReportItemCount()) ?? 0
        } catch {
            lastError = error.localizedDescription
        }
        loadPresets()
        loadSubscriptions()
    }

    func deleteOldest(_ n: Int = 10) {
        do {
            let removed = try storage.deleteOldestReports(count: n)
            SpotlightIndexer.shared.remove(reportIDs: removed)
            refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func applyRetention() {
        guard retentionDays > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(retentionDays) * 86_400)
        do {
            let removed = try storage.deleteReports(olderThan: cutoff)
            SpotlightIndexer.shared.remove(reportIDs: removed)
            try storage.pruneSeenItems()
            refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Sidebar selection (P4-6)

    enum SidebarSection: String, Hashable {
        case history
        case search
        case entities
    }
    @Published var sidebarSelection: SidebarSection = .history

    // MARK: - Search (P4-6)

    func searchReports(_ query: String) -> [StorageManager.SearchHit] {
        (try? storage.searchReports(query)) ?? []
    }

    // MARK: - Source health (P4-5)

    func sourceHealthRows(days: Int = 30) throws -> [SourceHealth] {
        try storage.sourceHealth(days: days)
    }

    // MARK: - Feedback (P4-4)

    func feedback(target: Feedback.Target, targetID: String) -> [Feedback] {
        (try? storage.feedback(target: target, targetID: targetID)) ?? []
    }

    func addFeedback(target: Feedback.Target, targetID: String, kind: Feedback.Kind, note: String? = nil) {
        let entry = Feedback(
            id: UUID(),
            target: target,
            targetID: targetID,
            kind: kind,
            note: note,
            createdAt: Date()
        )
        do {
            try storage.recordFeedback(entry)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func removeFeedback(target: Feedback.Target, targetID: String, kind: Feedback.Kind) {
        do {
            try storage.deleteFeedback(target: target, targetID: targetID, kind: kind)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func clusters(forReport reportID: UUID) -> [BriefingResult.Cluster] {
        (try? storage.clusters(for: reportID)) ?? []
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

    private func deliverWebhook(report: Report, config: WebhookConfig) async {
        let markdown = (try? storage.loadMarkdown(for: report)) ?? ""
        let clusters = (try? storage.clusters(for: report.id)) ?? []
        let outcome = await WebhookDeliverer.deliver(
            report: report,
            markdown: markdown,
            clusters: clusters,
            config: config
        )
        if !outcome.isSuccess {
            let label = outcome.status.map { "HTTP \($0)" } ?? (outcome.errorMessage ?? "unknown error")
            lastError = "Webhook \(config.format.displayName) failed: \(label)"
        }
    }

    /// Used by the "Send test" button in `TopicPresetEditor`.
    func sendWebhookTest(config: WebhookConfig) async -> WebhookDeliverer.Outcome {
        await WebhookDeliverer.sendTest(config: config)
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

    /// Build a `BriefChatSession` for the given report. Returns nil when no
    /// LLM provider is configured (caller can show the Settings nag).
    @MainActor
    func makeBriefChatSession(for report: Report) -> BriefChatSession? {
        guard let llm = makeLLMClient() else { return nil }
        return BriefChatSession(
            report: report,
            storage: storage,
            llm: llm,
            model: activeModelOverride
        )
    }

    /// P5-6: scan opt-in presets, fire a weekly synth for each that's due.
    /// Called once at launch and after each preset run. No-op for presets
    /// without the toggle or that already ran in the past 7 days.
    func runDueWeeklyDigests() async {
        guard let llm = makeLLMClient() else { return }
        let due = presets.filter { WeeklySynthesizer.isDue($0) }
        guard !due.isEmpty else { return }
        let synthesizer = WeeklySynthesizer(storage: storage, llm: llm, model: activeModelOverride)
        for preset in due {
            do {
                _ = try await synthesizer.synthesize(for: preset)
            } catch {
                lastError = "Weekly digest for \(preset.name) failed: \(error.localizedDescription)"
            }
        }
        refresh()
    }

    /// Manual trigger used by the "Run now" button in the preset editor.
    func runWeeklyDigestNow(for preset: TopicPreset) async {
        guard let llm = makeLLMClient() else {
            lastError = missingProviderMessage
            return
        }
        let synthesizer = WeeklySynthesizer(storage: storage, llm: llm, model: activeModelOverride)
        do {
            if let stored = try await synthesizer.synthesize(for: preset) {
                refresh()
                selectedReportID = stored.id
            } else {
                lastError = "No daily briefs in the past 7 days for \(preset.name)."
            }
        } catch {
            lastError = "Weekly digest failed: \(error.localizedDescription)"
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
            model: activeModelOverride,
            queryRewritingEnabled: queryRewritingEnabled,
            contradictionDetectionEnabled: contradictionDetectionEnabled,
            entityExtractionEnabled: entityExtractionEnabled,
            counterpointsEnabled: counterpointsEnabled
        )
    }

    // MARK: - Entities (P5-2)

    func topEntities(limit: Int = 100, kind: Entity.Kind? = nil) -> [Entity] {
        (try? storage.topEntities(limit: limit, kind: kind)) ?? []
    }

    func mentions(forEntity id: UUID) -> [EntityTimelineRow] {
        (try? storage.mentions(forEntity: id)) ?? []
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
