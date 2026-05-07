import Foundation

/// User-supplied subscription to a specific source instance — e.g. a YouTube
/// channel ID, an RSS feed URL, a subreddit name. Phase 1 doesn't surface
/// subscriptions in the UI yet (HN is global), but adapters already accept
/// them so later phases plug in without protocol churn.
struct SourceSubscription: Identifiable, Codable, Hashable {
    let id: UUID
    let kind: SourceKind
    let identifier: String
    let label: String

    init(
        id: UUID = UUID(),
        kind: SourceKind,
        identifier: String,
        label: String
    ) {
        self.id = id
        self.kind = kind
        self.identifier = identifier
        self.label = label
    }
}
