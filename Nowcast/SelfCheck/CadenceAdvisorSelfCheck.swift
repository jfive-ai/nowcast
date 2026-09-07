#if DEBUG
import Foundation

@MainActor
enum CadenceAdvisorSelfCheck {
    static func run(storage: StorageManager, check: (String, Bool) -> Void) async {
        let daily = Cadence.dailyAt(hour: 9, minute: 30)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let reportID = UUID()
        func runs(_ fresh: [Int], total: Int = 10, error: String? = nil) -> [SourceRun] {
            fresh.enumerated().map { index, count in
                let date = start.addingTimeInterval(Double(index) * 3_600)
                return SourceRun(id: UUID(), reportID: reportID, sourceKind: .hackerNews,
                                 startedAt: date, finishedAt: date.addingTimeInterval(1),
                                 itemsReturned: total, itemsFresh: count, errorMessage: error)
            }
        }
        func suggestion(_ fresh: [Int], cadence: Cadence = .dailyAt(hour: 9, minute: 30)) -> CadenceSuggestion? {
            CadenceAdvisor.suggest(recentRuns: runs(fresh), currentCadence: cadence)
        }
        check("P7-4: five zero-fresh runs suggest slower cadence", suggestion([0, 0, 0, 0, 0])?.direction == .down)
        check("P7-4: five 80%-fresh runs suggest faster cadence", suggestion([8, 8, 8, 8, 8])?.direction == .up)
        check("P7-4: mid-band has no suggestion", suggestion([5, 5, 5, 5, 5]) == nil)
        check("P7-4: fewer than three runs has no suggestion", suggestion([0, 0]) == nil)
        check("P7-4: 10% is not in the low band", suggestion([1, 1, 1]) == nil)
        check("P7-4: newest mixed signal interrupts a streak", suggestion([0, 0, 0, 0, 5]) == nil)
        check("P7-4: three latest consistent runs suffice", suggestion([5, 5, 0, 0, 0])?.direction == .down)
        check("P7-4: empty fetches are not evidence", CadenceAdvisor.suggest(recentRuns: runs([0, 0, 0], total: 0), currentCadence: daily) == nil)
        check("P7-4: failed fetches are not evidence", CadenceAdvisor.suggest(recentRuns: runs([0, 0, 0], error: "offline"), currentCadence: daily) == nil)
        check("P7-4: manual presets are never promoted", suggestion([9, 9, 9], cadence: .manual) == nil)
        check("P7-4: hourly cannot be promoted further", suggestion([9, 9, 9], cadence: .everyNHours(hours: 1)) == nil)
        check("P7-4: weekly cannot be demoted further", suggestion([0, 0, 0], cadence: .weeklyAt(weekday: 3, hour: 9, minute: 30)) == nil)
        check("P7-4: slower daily schedule preserves local time", suggestion([0, 0, 0])?.proposedCadence == .weeklyAt(weekday: 2, hour: 9, minute: 30))
        check("P7-4: faster weekly schedule preserves local time", suggestion([9, 9, 9], cadence: .weeklyAt(weekday: 3, hour: 9, minute: 30))?.proposedCadence == daily)
        let oneRun = runs([0])[0]
        let multipleSources = (0..<5).map { _ in
            SourceRun(id: UUID(), reportID: reportID, sourceKind: .rss, startedAt: oneRun.startedAt,
                      finishedAt: oneRun.finishedAt, itemsReturned: 10, itemsFresh: 0, errorMessage: nil)
        }
        check("P7-4: five sources in one generation count as one run", CadenceAdvisor.suggest(recentRuns: multipleSources, currentCadence: daily) == nil)
        let mixed = runs([10, 10, 10]) + runs([0, 0, 0])
        check("P7-4: freshness is aggregated across each generation", CadenceAdvisor.suggest(recentRuns: mixed, currentCadence: daily) == nil)

        let suite = "nowcast.cadence-selfcheck.\(UUID())"
        if let defaults = UserDefaults(suiteName: suite) {
            defer { defaults.removePersistentDomain(forName: suite) }
            let memory = CadenceAdviceMemory(defaults: defaults)
            var preset = TopicPreset(name: "Cadence", query: "Rust", sources: [.hackerNews], cadence: daily)
            check("P7-4: old telemetry excluded on first observation", memory.evidenceSince(for: preset, now: start) == start)
            let relaunched = CadenceAdviceMemory(defaults: defaults)
            check("P7-4: evidence window survives relaunch", relaunched.evidenceSince(for: preset, now: start.addingTimeInterval(10)) == start)
            let dismissedAt = start.addingTimeInterval(20)
            relaunched.reset(for: preset, now: dismissedAt)
            check("P7-4: dismiss waits for new evidence across relaunch", memory.evidenceSince(for: preset) == dismissedAt)
            preset.cadence = .everyNHours(hours: 6)
            let appliedAt = start.addingTimeInterval(30)
            check("P7-4: applying a new cadence resets evidence", memory.evidenceSince(for: preset, now: appliedAt) == appliedAt)
            preset.query = "New topic"
            check("P7-4: collection changes reset evidence", memory.evidenceSince(for: preset, now: start) == start)
        } else { check("P7-4: isolated preferences suite opens", false) }

        do {
            let preset = TopicPreset(name: "Cadence pipeline probe", query: "Cadence \(UUID())", sources: [.hackerNews, .rss], cadence: daily)
            let other = TopicPreset(name: "Unrelated preset", query: "Other \(UUID())", sources: [.hackerNews])
            try storage.upsertPreset(preset)
            try storage.upsertPreset(other)
            var reportIDs: [UUID] = []
            defer {
                _ = try? storage.deleteReports(ids: reportIDs)
                try? storage.deletePreset(id: preset.id)
                try? storage.deletePreset(id: other.id)
            }
            let since = Date().addingTimeInterval(-1)
            let pipeline = ReportPipeline(adapters: [CadenceAdapter(kind: .hackerNews), CadenceAdapter(kind: .rss)], storage: storage, llm: MockLLMClient())
            let report = try await pipeline.generate(topic: preset.query, window: .today, sources: preset.sources, presetID: preset.id)
            reportIDs.append(report.id)
            let otherReport = try storage.insertReport(Report(id: UUID(), presetID: other.id, topic: other.query,
                                                             window: .today, generatedAt: Date().addingTimeInterval(1),
                                                             markdownPath: "", byteSize: 0, sourceCount: 0), markdown: "Other preset")
            reportIDs.append(otherReport.id)
            let weekly = try storage.insertReport(Report(id: UUID(), presetID: preset.id, topic: preset.query,
                                                        window: .today, generatedAt: Date(), markdownPath: "",
                                                        byteSize: 0, sourceCount: 0, kind: .weeklyDigest), markdown: "Weekly synthesis")
            reportIDs.append(weekly.id)
            for _ in 0..<3 {
                try await Task.sleep(nanoseconds: 5_000_000)
                do {
                    _ = try await pipeline.generate(topic: preset.query, window: .today, sources: preset.sources, presetID: preset.id)
                    check("P7-4: repeated inputs trigger no-fresh path", false)
                } catch PipelineError.noFreshItems { }
            }
            let recent = try storage.recentSourceRuns(forPreset: preset.id, since: since)
            check("P7-4: quiet runs stay anchored to their own preset", recent.count == 8 && recent.allSatisfy { $0.reportID == report.id || $0.reportID == weekly.id })
            check("P7-4: weekly anchor retains quiet-run evidence", recent.filter { $0.reportID == weekly.id }.count == 6)
            check("P7-4: source rows group into four generation timestamps", Set(recent.map(\.startedAt)).count == 4)
            check("P7-4: real no-fresh pipeline history suggests slower cadence", CadenceAdvisor.suggest(recentRuns: recent, currentCadence: daily)?.direction == .down)
            let otherRuns = try storage.recentSourceRuns(forPreset: other.id, since: since)
            check("P7-4: unrelated preset receives no quiet-run evidence", otherRuns.isEmpty)
            let latest = try storage.recentSourceRuns(forPreset: preset.id, since: since, limit: 1)
            check("P7-4: history limit preserves all sources of last generation", latest.count == 2)
            let memorySuite = "nowcast.cadence-manual-selfcheck.\(UUID())"
            guard let defaults = UserDefaults(suiteName: memorySuite) else { throw CocoaError(.fileReadUnknown) }
            defer { defaults.removePersistentDomain(forName: memorySuite) }
            let memory = CadenceAdviceMemory(defaults: defaults)
            memory.reset(for: preset) // Start a manual run: discard the scheduled streak.
            for _ in 0..<3 {
                do {
                    _ = try await pipeline.generate(topic: preset.query, window: .today, sources: preset.sources, presetID: preset.id)
                } catch PipelineError.noFreshItems { }
            }
            memory.reset(for: preset) // End the manual run: discard its source health rows.
            let afterManual = try storage.recentSourceRuns(forPreset: preset.id, since: memory.evidenceSince(for: preset))
            check("P7-4: rapid manual runs cannot drive cadence advice after cutoff reset", afterManual.isEmpty)
            let afterDismissal = try storage.recentSourceRuns(forPreset: preset.id, since: Date())
            check("P7-4: dismissal cutoff excludes previous evidence", afterDismissal.isEmpty)
        } catch { check("P7-4: production history probe (\(error))", false) }
    }

    private struct CadenceAdapter: SourceAdapter {
        let kind: SourceKind
        func fetch(query: String, window: TimeWindow, subscriptions: [SourceSubscription]) async throws -> [RawItem] {
            let key = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "probe"
            return [RawItem(title: "Cadence source probe", url: URL(string: "https://mock.example/cadence/\(key)/\(kind.rawValue)")!,
                            publishedAt: Date(), snippet: "An unchanged source item", transcript: nil, sourceKind: kind, author: nil)]
        }
    }
}
#endif
