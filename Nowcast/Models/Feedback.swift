import Foundation

/// User feedback on either a whole report or a single cluster within it.
/// Persisted to `feedback` (schema v6). Drives the personalization signal
/// fed back into the next prompt run.
struct Feedback: Identifiable, Hashable, Codable {
    enum Target: String, Codable { case report, cluster }
    enum Kind: String, Codable, CaseIterable {
        case star
        case dismiss
        case thumbsUp = "thumbs_up"
        case thumbsDown = "thumbs_down"
        case hallucination

        var displayName: String {
            switch self {
            case .star:          return "Star"
            case .dismiss:       return "Dismiss"
            case .thumbsUp:      return "Thumbs up"
            case .thumbsDown:    return "Thumbs down"
            case .hallucination: return "Hallucination"
            }
        }

        var symbol: String {
            switch self {
            case .star:          return "star.fill"
            case .dismiss:       return "eye.slash"
            case .thumbsUp:      return "hand.thumbsup.fill"
            case .thumbsDown:    return "hand.thumbsdown.fill"
            case .hallucination: return "exclamationmark.triangle.fill"
            }
        }
    }

    let id: UUID
    let target: Target
    let targetID: String
    let kind: Kind
    let note: String?
    let createdAt: Date
}
