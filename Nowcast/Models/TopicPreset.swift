import Foundation

struct TopicPreset: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var query: String
    var sources: [SourceKind]
    var createdAt: Date
    var lastRunAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        query: String,
        sources: [SourceKind],
        createdAt: Date = Date(),
        lastRunAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.query = query
        self.sources = sources
        self.createdAt = createdAt
        self.lastRunAt = lastRunAt
    }
}
