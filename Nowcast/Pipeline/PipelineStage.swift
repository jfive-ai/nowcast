import Foundation

/// Events the pipeline emits while it's running (P5-5). Consumed by
/// `AppState` to drive a live stage-by-stage timeline in the UI so the
/// user can see where a generation is spending its time.
enum PipelineStage: Hashable, Codable {
    case started(topic: String, sourceCount: Int)
    case rewriting
    case fetching(SourceKind)
    case fetched(SourceKind, itemCount: Int)
    case deduping(beforeCount: Int)
    case llmRequested
    case llmReceived(tokens: Int?)
    case validating
    case enrichingEntities
    case writingCounterpoints
    case writing
    case done(reportID: UUID)
    case failed(message: String)

    var displayName: String {
        switch self {
        case .started(let t, _):    return "Starting \(t)"
        case .rewriting:            return "Rewriting query"
        case .fetching(let k):      return "Fetching \(k.displayName)"
        case .fetched(let k, let n): return "Fetched \(n) from \(k.displayName)"
        case .deduping:             return "Deduplicating"
        case .llmRequested:         return "Calling LLM"
        case .llmReceived(let t):   return t.map { "LLM responded (\($0) tokens)" } ?? "LLM responded"
        case .validating:           return "Validating citations"
        case .enrichingEntities:    return "Extracting entities"
        case .writingCounterpoints: return "Generating counterpoints"
        case .writing:              return "Writing report"
        case .done:                 return "Done"
        case .failed(let m):        return "Failed — \(m)"
        }
    }

    var symbol: String {
        switch self {
        case .started:              return "play.circle"
        case .rewriting:            return "text.magnifyingglass"
        case .fetching:             return "arrow.down.circle"
        case .fetched:              return "tray.and.arrow.down.fill"
        case .deduping:             return "scissors"
        case .llmRequested:         return "brain.head.profile"
        case .llmReceived:          return "checkmark.bubble"
        case .validating:           return "shield.checkered"
        case .enrichingEntities:    return "person.crop.circle.dashed"
        case .writingCounterpoints: return "exclamationmark.triangle"
        case .writing:              return "doc.text"
        case .done:                 return "checkmark.seal.fill"
        case .failed:               return "xmark.octagon.fill"
        }
    }

    var isTerminal: Bool {
        switch self {
        case .done, .failed: return true
        default: return false
        }
    }
}

/// Aggregated state the UI binds to. The pipeline pushes new stages into
/// `history` via the callback; the UI just reads.
struct GenerationState: Equatable {
    /// FIX (codex review PR #60 P1): identifies this generation run so
    /// the AppState's delayed cleanup can match exactly the run it
    /// scheduled, instead of failing equality if a queued progress
    /// update mutates `history` between snapshot and clear.
    let runID: UUID
    let topic: String
    let startedAt: Date
    var history: [Event] = []
    var current: PipelineStage?

    struct Event: Identifiable, Hashable {
        let id = UUID()
        let stage: PipelineStage
        let at: Date
    }

    /// True once the pipeline pushed the terminal `.done` event.
    var isFinished: Bool {
        if case .done = current { return true }
        return false
    }

    mutating func push(_ stage: PipelineStage, at: Date = Date()) {
        history.append(Event(stage: stage, at: at))
        current = stage
    }

    /// FIX (codex review PR #60 P2): freeze the elapsed clock once the
    /// pipeline reports `.done` (so the overlay shows total runtime).
    /// While generation is still in flight, advance against `Date()` so
    /// the clock doesn't pin to whatever the most recent stage timestamp
    /// was — long LLM gaps used to freeze the timer.
    var elapsed: TimeInterval {
        let end: Date
        if isFinished, let last = history.last?.at {
            end = last
        } else {
            end = Date()
        }
        return end.timeIntervalSince(startedAt)
    }
}
