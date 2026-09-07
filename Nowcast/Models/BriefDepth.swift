import Foundation

enum BriefDepth: String, Codable, CaseIterable, Identifiable {
    case skim, standard, deep
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }

    var instruction: String {
        switch self {
        case .skim: return "Aim for 150–250 words. Prioritize the headline takeaways; keep each story to one or two sentences."
        case .standard: return "Aim for 400–500 words, with two or three sentences per story."
        case .deep: return "Aim for 800–1,000 words when the inputs support it. Explain context, mechanisms, tradeoffs, and concrete evidence for each story. Never pad thin inputs."
        }
    }
}
