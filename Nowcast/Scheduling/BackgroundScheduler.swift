import Foundation

/// Schedules per-preset background runs using `NSBackgroundActivityScheduler`.
///
/// macOS gives us a window — not a precise time — for activity to run.
/// That's the right shape for "every N hours" but it's a coarse
/// approximation for "daily at 8am" / "weekly Mon 9am". For those cases we
/// translate the target instant into an interval-from-now and re-register
/// each run, so wall-clock drift accumulates only across one cycle.
@MainActor
final class BackgroundScheduler {
    /// Called when a preset's scheduled window fires.
    var onFire: ((UUID) async -> Void)?

    private var activities: [UUID: NSBackgroundActivityScheduler] = [:]

    func reschedule(_ presets: [TopicPreset]) {
        let active = Set(presets.map(\.id))
        for id in activities.keys where !active.contains(id) {
            cancel(presetID: id)
        }
        for preset in presets {
            schedule(preset)
        }
    }

    func cancel(presetID: UUID) {
        if let existing = activities.removeValue(forKey: presetID) {
            existing.invalidate()
        }
    }

    func cancelAll() {
        for activity in activities.values { activity.invalidate() }
        activities.removeAll()
    }

    // MARK: - Internals

    private func schedule(_ preset: TopicPreset) {
        cancel(presetID: preset.id)
        guard let next = preset.cadence.nextFireDate(after: Date()) else { return }

        let interval = max(60, next.timeIntervalSinceNow)

        let activity = NSBackgroundActivityScheduler(identifier: "com.jfive-ai.nowcast.preset.\(preset.id.uuidString)")
        activity.qualityOfService = .utility
        activity.repeats = false
        activity.interval = interval
        // Allow the system a 25% wiggle room either side of `interval`.
        activity.tolerance = max(60, interval * 0.25)

        let presetID = preset.id
        activity.schedule { [weak self] completion in
            Task { @MainActor in
                await self?.onFire?(presetID)
                completion(.finished)
                // Re-register so the next cycle is queued from a fresh "now".
                self?.rescheduleSelf(presetID: presetID)
            }
        }

        activities[preset.id] = activity
    }

    /// Re-schedule a single preset by id. Looked up via `onFire`'s side effects;
    /// here we just clear the slot so the next `reschedule(_:)` fills it.
    private func rescheduleSelf(presetID: UUID) {
        activities[presetID] = nil
    }
}
