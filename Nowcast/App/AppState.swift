import Foundation
import Combine

/// App-wide observable state. Owns the storage handle, the current LLM
/// client, and the pipeline. Rebuilds the LLM client when the API key
/// changes in Settings.
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var reports: [Report] = []
    @Published private(set) var totalReportBytes: Int64 = 0
    @Published var lastError: String?
    @Published var isGenerating: Bool = false

    @Published var openAIAPIKey: String {
        didSet { rebuildPipeline() }
    }

    /// Days to retain reports. 0 means keep forever.
    @Published var retentionDays: Int {
        didSet { UserDefaults.standard.set(retentionDays, forKey: Self.retentionDaysKey) }
    }

    let storage: StorageManager

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
    }

    // MARK: - Public actions

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

    func generate(topic: String, window: TimeWindow, sources: [SourceKind]) async {
        guard let pipeline else {
            lastError = "Set your OpenAI API key in Settings first."
            return
        }
        isGenerating = true
        defer { isGenerating = false }
        do {
            _ = try await pipeline.generate(
                topic: topic,
                window: window,
                sources: sources,
                presetID: nil,
                subscriptions: []
            )
            refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refresh() {
        do {
            reports = try storage.listReports()
            totalReportBytes = try storage.totalReportBytes()
        } catch {
            lastError = error.localizedDescription
        }
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
