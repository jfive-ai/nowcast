import Foundation

/// One adapter execution within a report run. Captures the outcome so the
/// user can see which sources are reliable, which are dead, and which are
/// pulling weight.
struct SourceRun: Identifiable, Hashable {
    let id: UUID
    let reportID: UUID
    let sourceKind: SourceKind
    let startedAt: Date
    let finishedAt: Date?
    let itemsReturned: Int
    let itemsFresh: Int
    let errorMessage: String?

    var latencySeconds: Double? {
        guard let finishedAt else { return nil }
        return finishedAt.timeIntervalSince(startedAt)
    }

    var succeeded: Bool { errorMessage == nil }
}

/// Rolling aggregate for the source health UI.
struct SourceHealth: Identifiable, Hashable {
    var id: SourceKind { sourceKind }
    let sourceKind: SourceKind
    let runs: Int
    let successes: Int
    let totalReturned: Int
    let totalFresh: Int
    let avgLatencySeconds: Double?
    let lastError: String?
    let lastRunAt: Date?

    var successRate: Double { runs == 0 ? 0 : Double(successes) / Double(runs) }
    var freshnessRate: Double {
        totalReturned == 0 ? 0 : Double(totalFresh) / Double(totalReturned)
    }
}
