import Foundation

protocol SourceAdapter {
    var kind: SourceKind { get }
    func fetch(query: String,
               window: TimeWindow,
               subscriptions: [SourceSubscription]) async throws -> [RawItem]
}

extension String {
    /// `nil` for the empty string — lets adapters collapse empty feed
    /// fields into optionals.
    var nonEmpty: String? { isEmpty ? nil : self }
}
