import Foundation

/// How a finished report is surfaced to the user.
/// Email is added in Phase 2.5.
enum DeliveryChannel: String, Codable, CaseIterable, Identifiable, Hashable {
    case inApp
    case notification
    case menuBar

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .inApp:        return "In-app only"
        case .notification: return "macOS notification"
        case .menuBar:      return "Menu bar badge"
        }
    }
}
