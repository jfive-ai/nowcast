import Foundation

enum BriefTone: String, Codable, CaseIterable, Identifiable {
    case neutral, opinionated, technical
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }

    var instruction: String {
        switch self {
        case .neutral: return "Use balanced, factual language. Distinguish supported observations from uncertainty; avoid editorial judgments."
        case .opinionated: return "Offer a clear editorial take grounded in the inputs. Label judgments and uncertainty, and distinguish your interpretation from reported facts."
        case .technical: return "Use precise domain terminology and explain mechanisms, limitations, and implementation details. Include code only when supported by the inputs."
        }
    }
}
