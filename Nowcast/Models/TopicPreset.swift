import Foundation

struct TopicPreset: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var query: String
    var window: TimeWindow
    var sources: [SourceKind]
    var cadence: Cadence
    var deliveryChannels: [DeliveryChannel]
    var createdAt: Date
    var lastRunAt: Date?
    /// P5-6: when true, a weekly synthesis runs once per week over the
    /// preset's daily reports.
    var weeklyDigestEnabled: Bool
    /// P5-6: when the synthesizer last ran for this preset. Drives
    /// scheduler eligibility (now ≥ last_weekly_at + 7 days).
    var lastWeeklyAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        query: String,
        window: TimeWindow = .today,
        sources: [SourceKind],
        cadence: Cadence = .manual,
        deliveryChannels: [DeliveryChannel] = [.inApp],
        createdAt: Date = Date(),
        lastRunAt: Date? = nil,
        weeklyDigestEnabled: Bool = false,
        lastWeeklyAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.query = query
        self.window = window
        self.sources = sources
        self.cadence = cadence
        self.deliveryChannels = deliveryChannels
        self.createdAt = createdAt
        self.lastRunAt = lastRunAt
        self.weeklyDigestEnabled = weeklyDigestEnabled
        self.lastWeeklyAt = lastWeeklyAt
    }
}
