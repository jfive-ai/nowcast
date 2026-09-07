import Foundation

struct CadenceSuggestion: Hashable {
    enum Direction: String { case up, down }
    let direction: Direction
    let currentCadence: Cadence
    let proposedCadence: Cadence
    let reason: String
}
