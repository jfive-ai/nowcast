import SwiftUI

/// UI tint for each feedback kind, shared by the report-level toolbar toggles
/// and the per-cluster feedback controls so the colors stay consistent.
extension Feedback.Kind {
    var tint: Color {
        switch self {
        case .thumbsUp:      return .green
        case .thumbsDown:    return .orange
        case .hallucination: return .red
        case .star:          return .yellow
        case .dismiss:       return .gray
        }
    }
}
