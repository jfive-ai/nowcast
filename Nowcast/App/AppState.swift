import Foundation
import Combine

/// App-wide observable state. Owns the storage handle, the current LLM
/// client, the pipeline, and the background scheduler. Rebuilds the LLM
/// client when the API key changes in Settings.
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var reports: [Report] = []
    @Published private(set) var presets: [TopicPreset] = []
    @Published private(set) var totalReportBytes: Int64 = 0
    @Published private(set) var unreadCount: Int = 0
    @Published var lastError: String?
    @Published var isGenerating: Bool = false
    /// Bound by `ContentView` so external triggers (notifications, menu bar)
    /// can change which report is shown.
    @Published var selectedReportID: UUID?

    @Published var openAIAPIKey: String {
        didSet { rebuildPipeline() }
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

    init() {
        // Storage MUST come up; if it doesn't, the app can't function.
        do {
            self.storage = try StorageManager()
        } catch {
            fatalError("Failed to open Nowcast database: \(error)")
        }

        self.openAIAPIKey = KeychainStore.shared.getSecret(account: KeychainAccount.openAI) ?? ""
        self.retentionDays = UserDefaults.standard.object(forKey: Self.retentionDaysKey) as? Int
            ?? Self.defaultRetentionDays

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
        do {
            if key.isEmpty {
                try KeychainStore.shared.delete(account: KeychainAccount.openAI)
            } else {
                try KeychainStore.shared.setSecret(key, account: KeychainAccount.openAI)
            }
            openAIAPIKey = key
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
            lastError = "Set your OpenAI API key in Settings first."
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
                subscriptions: []
            )
            refresh()

            if let presetID,
               let preset = presets.first(where: { $0.id == presetID }) {
                if preset.deliveryChannels.contains(.notification) {
                    await NotificationManager.shared.postReportReady(report)
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

    // MARK: - Internals

    private func rebuildPipeline() {
        guard !openAIAPIKey.isEmpty else {
            pipeline = nil
            return
        }
        let llm = OpenAIClient(apiKey: openAIAPIKey)
        pipeline = ReportPipeline(
            adapters: [HackerNewsAdapter()],
            storage: storage,
            llm: llm
        )
    }
}
