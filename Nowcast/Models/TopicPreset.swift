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
    /// When true, a weekly synthesis runs once per week over the
    /// preset's daily reports.
    var weeklyDigestEnabled: Bool
    /// When the synthesizer last ran for this preset. Drives
    /// scheduler eligibility (now ≥ last_weekly_at + 7 days).
    var lastWeeklyAt: Date?
    var depth: BriefDepth
    var tone: BriefTone

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
        lastWeeklyAt: Date? = nil,
        depth: BriefDepth = .standard,
        tone: BriefTone = .neutral
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
        self.depth = depth
        self.tone = tone
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, query, window, sources, cadence, deliveryChannels, createdAt, lastRunAt
        case weeklyDigestEnabled, lastWeeklyAt, depth, tone
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try values.decode(UUID.self, forKey: .id),
            name: try values.decode(String.self, forKey: .name),
            query: try values.decode(String.self, forKey: .query),
            window: try values.decode(TimeWindow.self, forKey: .window),
            sources: try values.decode([SourceKind].self, forKey: .sources),
            cadence: try values.decode(Cadence.self, forKey: .cadence),
            deliveryChannels: try values.decode([DeliveryChannel].self, forKey: .deliveryChannels),
            createdAt: try values.decode(Date.self, forKey: .createdAt),
            lastRunAt: try values.decodeIfPresent(Date.self, forKey: .lastRunAt),
            weeklyDigestEnabled: try values.decodeIfPresent(Bool.self, forKey: .weeklyDigestEnabled) ?? false,
            lastWeeklyAt: try values.decodeIfPresent(Date.self, forKey: .lastWeeklyAt),
            depth: try values.decodeIfPresent(BriefDepth.self, forKey: .depth) ?? .standard,
            tone: try values.decodeIfPresent(BriefTone.self, forKey: .tone) ?? .neutral
        )
    }
}
