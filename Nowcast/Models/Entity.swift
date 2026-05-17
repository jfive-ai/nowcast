import Foundation

/// A named entity surfaced across one or more briefings (P5-2).
struct Entity: Identifiable, Hashable, Codable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case person
        case org
        case project
        case topic

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .person:  return "Person"
            case .org:     return "Organization"
            case .project: return "Project"
            case .topic:   return "Topic"
            }
        }

        var symbol: String {
            switch self {
            case .person:  return "person.circle"
            case .org:     return "building.2"
            case .project: return "cube"
            case .topic:   return "number"
            }
        }
    }

    let id: UUID
    let canonicalName: String
    let kind: Kind
    let firstSeenAt: Date
    let lastSeenAt: Date
    let mentionCount: Int

    init(id: UUID = UUID(),
         canonicalName: String,
         kind: Kind,
         firstSeenAt: Date = Date(),
         lastSeenAt: Date = Date(),
         mentionCount: Int = 0) {
        self.id = id
        self.canonicalName = canonicalName
        self.kind = kind
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
        self.mentionCount = mentionCount
    }
}

/// A single (entity ↔ report ↔ cluster) link materialized by `EntityExtractor`.
struct EntityMention: Hashable, Codable {
    let entityID: UUID
    let reportID: UUID
    /// Nullable because some mentions come from the TL;DR / signal sections,
    /// which don't belong to any single cluster.
    let clusterID: String?
}

/// Aggregated row used by the Entities view — entity plus the report rows
/// it appears in.
struct EntityTimelineRow: Identifiable {
    let report: Report
    let clusterID: String?
    let clusterHeadline: String?

    var id: String { "\(report.id.uuidString)-\(clusterID ?? "_")" }
}
