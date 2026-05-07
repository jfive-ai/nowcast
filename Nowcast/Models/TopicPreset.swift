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

    init(
        id: UUID = UUID(),
        name: String,
        query: String,
        window: TimeWindow = .today,
        sources: [SourceKind],
        cadence: Cadence = .manual,
        deliveryChannels: [DeliveryChannel] = [.inApp],
        createdAt: Date = Date(),
        lastRunAt: Date? = nil
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
    }
}
