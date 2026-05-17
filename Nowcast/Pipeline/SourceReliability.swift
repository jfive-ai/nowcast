import Foundation

/// Per-host reliability surface (P7-1). Derived entirely from existing
/// rows — `item.canonical_url` for the host, joined to `feedback` via
/// the cluster/report graph — so there's no new schema.
struct SourceReliability: Identifiable, Hashable {
    let host: String
    let mentions: Int
    let thumbsUp: Int
    let thumbsDown: Int
    let hallucinations: Int
    /// 0..100 score band. Computed by `formula(...)` so it stays testable.
    let score: Int

    var id: String { host }

    enum Band: String {
        case ok
        case mixed
        case watch

        var color: String {
            switch self {
            case .ok:    return "green"
            case .mixed: return "yellow"
            case .watch: return "red"
            }
        }

        var displayName: String {
            switch self {
            case .ok:    return "OK"
            case .mixed: return "Mixed"
            case .watch: return "Watch"
            }
        }
    }

    var band: Band {
        if score >= 70 { return .ok }
        if score >= 40 { return .mixed }
        return .watch
    }

    /// Smoothed score: punish hallucinations harder than thumbs-down,
    /// reward thumbs-up. The `+ 5` Laplace prior keeps brand-new hosts
    /// in the .mixed band until they accumulate enough signal.
    static func formula(mentions: Int, thumbsUp: Int, thumbsDown: Int, hallucinations: Int) -> Int {
        let denom = Double(max(1, mentions) + 5)
        let net = Double(thumbsUp) - Double(thumbsDown) - 2.0 * Double(hallucinations)
        // Map a [-1, +1] range to [0, 100] with a midpoint of 50.
        let normalized = max(-1.0, min(1.0, net / denom))
        let score = Int(((normalized + 1.0) / 2.0 * 100).rounded())
        return min(100, max(0, score))
    }
}
