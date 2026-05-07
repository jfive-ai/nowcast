import Foundation

/// How often a `TopicPreset` should auto-run. Stored as JSON in the
/// `topic_preset.cadence_json` column.
enum Cadence: Codable, Hashable {
    /// Run once every `hours` hours. `hours == 1` is the "hourly" preset.
    case everyNHours(hours: Int)
    /// Run once a day at the given local hour/minute.
    case dailyAt(hour: Int, minute: Int)
    /// Run once a week at the given weekday (1 = Sunday … 7 = Saturday)
    /// and local hour/minute.
    case weeklyAt(weekday: Int, hour: Int, minute: Int)
    /// No automatic schedule — preset only runs when the user triggers it.
    case manual

    var displayName: String {
        switch self {
        case .everyNHours(let h):
            return h == 1 ? "Hourly" : "Every \(h) hours"
        case .dailyAt(let h, let m):
            return String(format: "Daily at %02d:%02d", h, m)
        case .weeklyAt(let w, let h, let m):
            let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            let idx = max(1, min(7, w)) - 1
            return String(format: "Weekly · %@ %02d:%02d", names[idx], h, m)
        case .manual:
            return "Manual only"
        }
    }

    /// Compute the next firing instant strictly after `reference`.
    /// Returns nil for `.manual`.
    func nextFireDate(after reference: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .manual:
            return nil

        case .everyNHours(let hours):
            let interval = TimeInterval(max(1, hours) * 3600)
            return reference.addingTimeInterval(interval)

        case .dailyAt(let hour, let minute):
            var components = calendar.dateComponents([.year, .month, .day], from: reference)
            components.hour = hour
            components.minute = minute
            components.second = 0
            guard let candidate = calendar.date(from: components) else { return nil }
            if candidate > reference { return candidate }
            return calendar.date(byAdding: .day, value: 1, to: candidate)

        case .weeklyAt(let weekday, let hour, let minute):
            var components = DateComponents()
            components.weekday = weekday
            components.hour = hour
            components.minute = minute
            components.second = 0
            return calendar.nextDate(
                after: reference,
                matching: components,
                matchingPolicy: .nextTime
            )
        }
    }
}
