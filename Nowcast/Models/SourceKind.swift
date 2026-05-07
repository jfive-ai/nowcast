import Foundation

enum SourceKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case hackerNews
    case reddit
    case youtubeSearch
    case youtubeChannel
    case rss
    case web
    case news
    case xNitter

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hackerNews:    return "Hacker News"
        case .reddit:        return "Reddit"
        case .youtubeSearch: return "YouTube (search)"
        case .youtubeChannel: return "YouTube channel"
        case .rss:           return "RSS"
        case .web:           return "Web search"
        case .news:          return "News"
        case .xNitter:       return "X (via Nitter)"
        }
    }

    /// Phase 1 MVP only enables Hacker News.
    var isAvailableInMVP: Bool {
        self == .hackerNews
    }
}
