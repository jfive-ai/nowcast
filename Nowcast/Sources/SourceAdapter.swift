import Foundation

protocol SourceAdapter {
    var kind: SourceKind { get }
    func fetch(query: String,
               window: TimeWindow,
               subscriptions: [SourceSubscription]) async throws -> [RawItem]
}
