import Foundation

/// Monthly spend guardrail. PLAN.md flags runaway OpenAI cost on aggressive /
/// unattended schedules as a real risk: an hourly preset with an expensive
/// model can quietly rack up tens of dollars a day. Once the current calendar
/// month's recorded LLM spend reaches the user's cap, the pipeline refuses to
/// run (manual or scheduled) until the user raises or clears the cap.
///
/// A cap of 0 means "no limit". Pure + unit-checked by the headless self-check.
enum SpendGuard {
    static func isOverBudget(spentThisMonth: Double, budget: Double) -> Bool {
        budget > 0 && spentThisMonth >= budget
    }

    /// Start of the calendar month containing `now`.
    static func monthStart(_ now: Date, calendar: Calendar = .current) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
    }
}
