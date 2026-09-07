import Foundation

/// Keep dismissals and evidence windows across relaunch without changing the DB
/// schema. Start fresh when the cadence or collection settings change, and on
/// upgrade: older source_run rows did not reliably identify preset/run boundaries.
final class CadenceAdviceMemory {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func evidenceSince(for preset: TopicPreset, now: Date = Date()) -> Date {
        if let data = defaults.data(forKey: key(preset.id)),
           let entry = try? JSONDecoder().decode(Entry.self, from: data), entry.matches(preset) {
            return entry.since
        }
        reset(for: preset, now: now)
        return now
    }

    func reset(for preset: TopicPreset, now: Date = Date()) {
        let entry = Entry(query: preset.query, window: preset.window, sources: preset.sources,
                          cadence: preset.cadence, since: now)
        if let data = try? JSONEncoder().encode(entry) { defaults.set(data, forKey: key(preset.id)) }
    }

    func forget(_ id: UUID) { defaults.removeObject(forKey: key(id)) }
    private func key(_ id: UUID) -> String { "cadenceAdvice.v1.\(id.uuidString)" }

    private struct Entry: Codable {
        let query: String
        let window: TimeWindow
        let sources: [SourceKind]
        let cadence: Cadence
        let since: Date
        func matches(_ preset: TopicPreset) -> Bool {
            query == preset.query && window == preset.window && Set(sources) == Set(preset.sources)
                && cadence == preset.cadence
        }
    }
}
