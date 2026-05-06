import Foundation

enum TimeWindow: String, Codable, CaseIterable, Identifiable, Hashable {
    case lastHour = "1h"
    case today = "today"
    case last7Days = "7d"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lastHour: return "Last hour"
        case .today: return "Today"
        case .last7Days: return "Last 7 days"
        }
    }

    var earliestDate: Date {
        let now = Date()
        switch self {
        case .lastHour:
            return now.addingTimeInterval(-3600)
        case .today:
            return Calendar.current.startOfDay(for: now)
        case .last7Days:
            return now.addingTimeInterval(-7 * 24 * 3600)
        }
    }
}
