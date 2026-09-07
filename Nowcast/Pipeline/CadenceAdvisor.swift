import Foundation

/// Pure observation; no LLM calls or automatic schedule changes.
enum CadenceAdvisor {
    static let minimumRuns = 3
    static let windowSize = 5

    /// All source rows from a generation share startedAt. Aggregate them before
    /// evaluating a streak so three sources in one briefing never count as three runs.
    static func suggest(recentRuns: [SourceRun], currentCadence: Cadence) -> CadenceSuggestion? {
        guard currentCadence != .manual else { return nil }
        let groups = Dictionary(grouping: recentRuns, by: \.startedAt)
        let dates = groups.keys.sorted(by: >).prefix(windowSize)
        var direction: CadenceSuggestion.Direction?
        var streak = 0
        for date in dates {
            guard let rows = groups[date], !rows.isEmpty,
                  rows.allSatisfy({ $0.succeeded && $0.finishedAt != nil && $0.itemsReturned >= 0
                      && $0.itemsFresh >= 0 && $0.itemsFresh <= $0.itemsReturned }) else { break }
            let total = rows.reduce(0) { $0 + $1.itemsReturned }
            guard total > 0 else { break } // Empty/failed sources are not a freshness signal.
            let fresh = rows.reduce(0) { $0 + $1.itemsFresh }
            let ratio = Double(fresh) / Double(total)
            let band: CadenceSuggestion.Direction
            if ratio < 0.10 { band = .down }
            else if ratio >= 0.80 { band = .up }
            else { break }
            if let direction, direction != band { break }
            direction = band
            streak += 1
        }
        guard streak >= minimumRuns, let direction,
              let proposed = proposedCadence(from: currentCadence, direction: direction) else { return nil }
        let reason = direction == .down
            ? "Less than 10% of items were new in the last \(streak) runs. A slower schedule could reduce unnecessary work."
            : "At least 80% of items were new in the last \(streak) runs. A faster schedule could help you keep up."
        return CadenceSuggestion(direction: direction, currentCadence: currentCadence,
                                 proposedCadence: proposed, reason: reason)
    }

    private static func proposedCadence(from cadence: Cadence, direction: CadenceSuggestion.Direction) -> Cadence? {
        switch (cadence, direction) {
        case (.manual, _), (.everyNHours(hours: 1), .up), (.weeklyAt, .down): return nil
        case (.everyNHours(let hours), .up):
            guard hours > 1 else { return nil }
            return .everyNHours(hours: max(1, hours / 2))
        case (.everyNHours(let hours), .down):
            guard (1...24).contains(hours) else { return nil }
            if hours < 24 { return .everyNHours(hours: min(24, hours * 2)) }
            return .weeklyAt(weekday: 2, hour: 8, minute: 0)
        case (.dailyAt(let hour, let minute), .down):
            return .weeklyAt(weekday: 2, hour: hour, minute: minute)
        case (.dailyAt, .up): return .everyNHours(hours: 6)
        case (.weeklyAt(_, let hour, let minute), .up): return .dailyAt(hour: hour, minute: minute)
        }
    }
}
