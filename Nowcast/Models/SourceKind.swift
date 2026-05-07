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

    /// Adapters that ship in the current build. Editor toggles for
    /// `false` cases render disabled with a "Coming soon" badge.
    var isAvailable: Bool {
        switch self {
        case .hackerNews, .reddit, .rss, .news:
            return true
        case .youtubeSearch, .youtubeChannel, .web, .xNitter:
            return false
        }
    }
}
