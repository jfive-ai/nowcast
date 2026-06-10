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
    /// Live state of the in-flight generation. `nil` when idle.
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
    /// Costs one extra (cheap) LLM call per run.
    @Published var queryRewritingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(queryRewritingEnabled, forKey: Self.queryRewritingKey)
            rebuildPipeline()
        }
    }

    /// Second-pass LLM scan over the brief's claims for cross-source
    /// disagreement. Costs one extra LLM call.
    @Published var contradictionDetectionEnabled: Bool {
        didSet {
            UserDefaults.standard.set(contradictionDetectionEnabled, forKey: Self.contradictionDetectionKey)
            rebuildPipeline()
        }
    }

    /// Cross-brief entity extraction. One cheap LLM call per run, plus
    /// rule-based fallback.
    @Published var entityExtractionEnabled: Bool {
        didSet {
            UserDefaults.standard.set(entityExtractionEnabled, forKey: Self.entityExtractionKey)
            rebuildPipeline()
        }
    }

    /// Steel-man counter-argument + "what's not covered" pass. One extra
    /// LLM call per brief.
    @Published var counterpointsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(counterpointsEnabled, forKey: Self.counterpointsKey)
            rebuildPipeline()
        }
    }

    /// Smart auto-generated brief titles. One small extra LLM call per
    /// brief.
    @Published var smartTitlesEnabled: Bool {
        didSet {
            UserDefaults.standard.set(smartTitlesEnabled, forKey: Self.smartTitlesKey)
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
    static let smartTitlesKey = "nowcast.smart_titles_enabled"
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

        // Backfill the FTS index BEFORE the rest of init() runs. Keychain
        // calls later in this init can block under certain TCC states,
        // and the in-app search surface should cover historical reports
        // the moment the user opens the window — independent of any
        // prompt.
        try? storage.backfillFullTextIndexIfNeeded()

        // The headless self-check gate (NOWCAST_SELF_CHECK=1) must not
        // touch the Keychain: SecItemCopyMatching blocks on a user-approval
        // dialog when the freshly built binary's ad-hoc signature doesn't
        // match the one that stored the secret, hanging the gate before
        // the check starts. SelfCheck only needs storage + MockLLMClient.
#if DEBUG
        let headlessSelfCheck = ProcessInfo.processInfo.environment["NOWCAST_SELF_CHECK"] == "1"
#else
        let headlessSelfCheck = false
#endif
        if headlessSelfCheck {
            self.openAIAPIKey = ""
            self.anthropicAPIKey = ""
            self.youtubeAPIKey = ""
            self.braveAPIKey = ""
        } else {
            self.openAIAPIKey = KeychainStore.shared.getSecret(account: KeychainAccount.openAI) ?? ""
            self.anthropicAPIKey = KeychainStore.shared.getSecret(account: KeychainAccount.anthropic) ?? ""
            self.youtubeAPIKey = KeychainStore.shared.getSecret(account: KeychainAccount.youtube) ?? ""
            self.braveAPIKey = KeychainStore.shared.getSecret(account: KeychainAccount.braveSearch) ?? ""
        }
        self.smtpSettings = SMTPSettingsStore.shared.load()
        self.retentionDays = UserDefaults.standard.object(forKey: Self.retentionDaysKey) as? Int
            ?? Self.defaultRetentionDays
        self.queryRewritingEnabled = UserDefaults.standard.object(forKey: Self.queryRewritingKey) as? Bool ?? false
        self.contradictionDetectionEnabled = UserDefaults.standard.object(forKey: Self.contradictionDetectionKey) as? Bool ?? false
        self.entityExtractionEnabled = UserDefaults.standard.object(forKey: Self.entityExtractionKey) as? Bool ?? false
        self.counterpointsEnabled = UserDefaults.standard.object(forKey: Self.counterpointsKey) as? Bool ?? false
        self.smartTitlesEnabled = UserDefaults.standard.object(forKey: Self.smartTitlesKey) as? Bool ?? false

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
        if !headlessSelfCheck {
            Task { await NotificationManager.shared.requestAuthorization() }
        }

        // Rebuild the Spotlight index from the current report set so it
        // matches reality even if the user pruned reports while the app
        // was closed or installed a fresh build.
        SpotlightIndexer.shared.reindex(reports: reports) { [weak self] report in
            (try? self?.storage.loadMarkdown(for: report)) ?? ""
        }

        // At launch, fire any due weekly digests for opt-in presets.
        Task { [weak self] in
            await self?.runDueWeeklyDigests()
        }

        // Populate semantic-search vectors for any reports that pre-dated
        // the v14 migration. Runs detached so it never blocks UI;
        // embeddings just appear as they complete.
        backfillEmbeddingsIfNeeded()

        // Backfill big-story scores for reports that pre-dated v15.
        // Same detached pattern; pure DB work, no network.
        backfillBigStoryScoresIfNeeded()
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

        // Check for due weekly digests after every preset run, not only
        // at app startup — in a long-lived session a digest that becomes
        // due mid-week would otherwise wait until restart.
        await runDueWeeklyDigests()
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
        // The delayed clear below is keyed on a per-run UUID stored
        // *inside* the GenerationState. Pipeline progress events (incl.
        // the terminal `.done`) arrive via queued `Task { @MainActor }`
        // blocks and can mutate `generation` after a value snapshot, so a
        // value-equality check could fail forever and never clear the
        // overlay.
        let runID = UUID()
        generation = GenerationState(runID: runID, topic: topic, startedAt: Date())
        defer {
            isGenerating = false
            // Keep the final state visible for a moment so the user can
            // see the "Done" stage land before the overlay dismisses.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                if self.generation?.runID == runID { self.generation = nil }
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
                // Webhook delivery. Each preset can have N webhook
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
        // The big-story percentile depends on the full report set —
        // invalidate the cache so a freshly-inserted brief doesn't keep
        // comparing against a stale slice.
        invalidateBigStoryCache()
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
        // Always prune the seen-index (90d cutoff, independent of report
        // retention). Gating it on `retentionDays > 0` would give a
        // keep-reports-forever user unbounded seen_item growth — and
        // `filterUnseen` slows down proportionally.
        try? storage.pruneSeenItems()
        guard retentionDays > 0 else {
            refresh()
            return
        }
        let cutoff = Date().addingTimeInterval(-Double(retentionDays) * 86_400)
        do {
            let removed = try storage.deleteReports(olderThan: cutoff)
            SpotlightIndexer.shared.remove(reportIDs: removed)
            refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Sidebar selection

    enum SidebarSection: String, Hashable {
        case history
        case search
        case entities
    }
    @Published var sidebarSelection: SidebarSection = .history

    // MARK: - Search

    func searchReports(_ query: String) -> [StorageManager.SearchHit] {
        (try? storage.searchReports(query)) ?? []
    }

    // MARK: - Semantic search

    struct SemanticHit: Hashable, Identifiable {
        let reportID: UUID
        let topic: String
        let title: String?
        let generatedAt: Date
        /// Cosine similarity in [-1, +1]; UI renders this as a 0–100 bar.
        let score: Double
        var id: UUID { reportID }
        var displayTitle: String { (title?.isEmpty == false ? title : nil) ?? topic }
    }

    /// True when the OS shipped a sentence embedding for the current locale
    /// build. UI uses this to switch the semantic panel into an empty
    /// state instead of a "no results" wall.
    var semanticSearchAvailable: Bool { ReportEmbedder.shared.isAvailable }

    func semanticSearch(_ query: String, limit: Int = 25) -> [SemanticHit] {
        let cleaned = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty,
              let queryVector = ReportEmbedder.shared.embed(cleaned)
        else { return [] }
        guard let vectors = try? storage.allEmbeddings(), !vectors.isEmpty else { return [] }

        let reportByID = Dictionary(uniqueKeysWithValues: reports.map { ($0.id, $0) })
        let scored: [SemanticHit] = vectors.compactMap { entry in
            guard let report = reportByID[entry.reportID] else { return nil }
            let score = ReportEmbedder.similarity(queryVector, entry.vector)
            return SemanticHit(
                reportID: report.id,
                topic: report.topic,
                title: report.title,
                generatedAt: report.generatedAt,
                score: score
            )
        }
        return Array(scored.sorted { $0.score > $1.score }.prefix(limit))
    }

    // MARK: - Big story

    /// In-process cache of `(presetID? -> prior scores)` from the most
    /// recent fetch. Saves a SQL round-trip per History row render — the
    /// list redraws aggressively.
    private var bigStoryScoreCache: [UUID?: [Double]] = [:]

    /// True when `report.bigStoryScore` is in the top ~15% of recent
    /// scores for its preset (or clears the absolute floor when there's
    /// not enough history yet).
    func isBigStory(_ report: Report) -> Bool {
        guard let score = report.bigStoryScore, score > 0 else { return false }
        let key: UUID? = report.presetID
        let priors: [Double] = {
            if let cached = bigStoryScoreCache[key] { return cached }
            let fetched = (try? storage.bigStoryScores(presetID: key)) ?? []
            bigStoryScoreCache[key] = fetched
            return fetched
        }()
        // Remove THIS report's score from the comparison set so a brief
        // doesn't get to compare itself.
        let comparison = priors.filter { abs($0 - score) > .ulpOfOne || priors.count == 1 }
        return BigStoryScorer.isBig(score: score, comparison: comparison)
    }

    /// Invalidate the per-preset scores cache. Called whenever the report
    /// list refreshes — keeps cache from going stale after a new brief.
    func invalidateBigStoryCache() { bigStoryScoreCache.removeAll() }

    /// Backfill scores for legacy reports that pre-dated v15. Pure DB +
    /// CPU work; runs detached.
    func backfillBigStoryScoresIfNeeded() {
        Task.detached { [storage] in
            let ids = (try? storage.reportIDsMissingBigStory(limit: 1000)) ?? []
            guard !ids.isEmpty else { return }
            for reportID in ids {
                let clusters = (try? storage.clusters(for: reportID)) ?? []
                guard !clusters.isEmpty else {
                    // No structured clusters → leave NULL so we don't pin a
                    // misleading zero. The next live run that produces
                    // structured output will populate them naturally.
                    continue
                }
                let synthetic = BriefingResult(
                    tldr: [], clusters: clusters, signal: "", lowConfidence: false
                )
                let outcome = BigStoryScorer.score(synthetic)
                guard outcome.score > 0 else { continue }
                try? storage.saveBigStory(
                    reportID: reportID,
                    score: outcome.score,
                    headline: outcome.headline
                )
            }
        }
    }

    /// One-shot backfill that runs in the background at launch: for every
    /// report missing an embedding, embed `topic + title + markdown[:1500]`
    /// and write the vector back. Batches in groups of 25 to keep the
    /// transaction load even.
    func backfillEmbeddingsIfNeeded() {
        guard ReportEmbedder.shared.isAvailable else { return }
        Task.detached { [storage] in
            let pending = (try? storage.reportsMissingEmbedding(limit: 1000)) ?? []
            guard !pending.isEmpty else { return }
            for row in pending {
                let url = AppPaths.reportURL(for: row.markdownPath)
                let body = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                let text = ReportEmbedder.makeIndexText(
                    topic: row.topic,
                    title: row.title,
                    markdown: body
                )
                guard let vector = ReportEmbedder.shared.embed(text) else { continue }
                try? storage.saveEmbedding(reportID: row.id, vector: vector)
            }
        }
    }

    // MARK: - Source health

    func sourceHealthRows(days: Int = 30) throws -> [SourceHealth] {
        try storage.sourceHealth(days: days)
    }

    // MARK: - Feedback

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

    /// Scan opt-in presets, fire a weekly synth for each that's due.
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
            counterpointsEnabled: counterpointsEnabled,
            smartTitlesEnabled: smartTitlesEnabled
        )
    }

    // MARK: - Entities

    func topEntities(limit: Int = 100, kind: Entity.Kind? = nil) -> [Entity] {
        (try? storage.topEntities(limit: limit, kind: kind)) ?? []
    }

    func mentions(forEntity id: UUID) -> [EntityTimelineRow] {
        (try? storage.mentions(forEntity: id)) ?? []
    }

    // MARK: - Items

    func itemsForReport(_ reportID: UUID) -> [PersistedItem] {
        (try? storage.itemsForReport(reportID)) ?? []
    }

    // MARK: - Source reliability

    /// Lazily-computed and cached for ~60s — the full join is expensive
    /// once the user has hundreds of items, and the popover hits this on
    /// every hover.
    private var reliabilityCache: (computedAt: Date, rows: [SourceReliability])?

    func sourceReliability(limit: Int = 50) -> [SourceReliability] {
        if let cache = reliabilityCache, Date().timeIntervalSince(cache.computedAt) < 60 {
            return Array(cache.rows.prefix(limit))
        }
        let rows = (try? storage.sourceReliability(limit: 500)) ?? []
        reliabilityCache = (Date(), rows)
        return Array(rows.prefix(limit))
    }

    /// Convenience for the popover badge — fast lookup by host.
    func reliability(for host: String) -> SourceReliability? {
        let normalized = host.lowercased().replacingOccurrences(of: "www.", with: "")
        return sourceReliability(limit: 500).first { $0.host == normalized }
    }

    // MARK: - Follow-up suggestions

    func suggestFollowUps(for report: Report,
                          tldr: [String],
                          clusterHeadlines: [String]) async -> [FollowUpSuggester.Suggestion] {
        guard let llm = makeLLMClient() else { return [] }
        let suggester = FollowUpSuggester(llm: llm, model: activeModelOverride)
        return await suggester.suggest(
            for: report,
            tldr: tldr,
            clusterHeadlines: clusterHeadlines,
            existingPresetNames: presets.map(\.name)
        )
    }

    // MARK: - Compare

    /// Reports the user can plausibly compare with `report` — same preset
    /// (if any), otherwise same topic string; never the report itself.
    /// Newest-first, capped at `limit`.
    func candidateReportsForCompare(_ report: Report, limit: Int = 10) -> [Report] {
        let same = reports.filter { other in
            guard other.id != report.id else { return false }
            if let pid = report.presetID {
                return other.presetID == pid
            }
            return other.topic.caseInsensitiveCompare(report.topic) == .orderedSame
        }
        return Array(same.prefix(limit))
    }

    /// Looks up the chronologically-prior report on the same topic/preset.
    /// Convenience for the "Compare with prior" shortcut. Bypasses the
    /// default candidate cap (intended for the compare-picker UI) so the
    /// lookup finds the immediately-prior report even on topics with many
    /// newer entries.
    func priorReport(for report: Report) -> Report? {
        candidateReportsForCompare(report, limit: .max)
            .first { $0.generatedAt < report.generatedAt }
    }

    /// In-app navigation target for the compare view.
    @Published var compareSelection: ComparePair?

    struct ComparePair: Hashable, Identifiable {
        let left: Report
        let right: Report
        var id: String { "\(left.id.uuidString)-\(right.id.uuidString)" }
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
