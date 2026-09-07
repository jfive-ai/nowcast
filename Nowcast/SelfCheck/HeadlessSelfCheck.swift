#if DEBUG
import Foundation

/// Headless entry point for CI and local regression runs.
///
/// When the app is launched with `NOWCAST_SELF_CHECK=1` in its environment,
/// `NowcastApp.init()` calls `HeadlessSelfCheck.runAndExit()` *before* any
/// SwiftUI scene is built. We construct a real `StorageManager`, run the
/// in-app `SelfCheck` harness against it, print the summary to stderr, and
/// `exit(0)` on pass / `exit(1)` on failure — no window, no Keychain, no
/// network. This is the project's automated regression gate (there is no
/// XCTest target yet); a GitHub Actions workflow builds the Debug app and
/// invokes it this way on every push / PR.
///
/// Pair with `NOWCAST_SUPPORT_DIR=<tmp>` (honored by `AppPaths`) so the run
/// writes into a throwaway container instead of the user's real database.
enum HeadlessSelfCheck {
    /// Environment variable that, when set to `"1"`, triggers the headless run.
    static let envFlag = "NOWCAST_SELF_CHECK"

    static var isRequested: Bool {
        ProcessInfo.processInfo.environment[envFlag] == "1"
    }

    /// Runs the self-check and terminates the process. Never returns.
    ///
    /// We are invoked from `main()` before the AppKit/SwiftUI run loop has
    /// started, so we pump the main run loop ourselves until the `@MainActor`
    /// self-check task completes. Blocking the main thread on a semaphore
    /// would deadlock the main-actor executor, so we poll instead.
    static func runAndExit() -> Never {
        let outcome = Outcome()

        Task { @MainActor in
            defer { outcome.finished = true }
            do {
                let storage = try StorageManager()
                let result = await SelfCheck.run(storage: storage)
                outcome.passed = result.passed
                outcome.summary = result.summary
                outcome.jsonSummary = result.jsonSummary
            } catch {
                outcome.passed = false
                outcome.summary = "✗ StorageManager init failed: \(error)"
                outcome.jsonSummary = "{\"passed\": false, \"error\": \"StorageManager init failed\"}"
            }
        }

        while !outcome.finished {
            // Service the main queue (where the @MainActor task resumes) for a
            // short slice, then re-check. `before:` keeps this from busy-spinning.
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }

        // Human-readable summary → stderr; machine-readable JSON → stdout when
        // requested (prod-27), so CI can parse per-check results.
        let banner = "\n=== Nowcast headless self-check ===\n"
        FileHandle.standardError.write(Data(banner.utf8))
        FileHandle.standardError.write(Data((outcome.summary + "\n").utf8))
        if ProcessInfo.processInfo.environment["NOWCAST_SELF_CHECK_JSON"] == "1" {
            FileHandle.standardOutput.write(Data((outcome.jsonSummary + "\n").utf8))
        }
        exit(outcome.passed ? 0 : 1)
    }

    /// Mutable result shared between the polling main thread and the
    /// main-actor task. All access happens on the main thread (the task hops
    /// to the main actor, the poll loop runs on the main thread between run-loop
    /// slices), so a plain reference type is race-free here.
    private final class Outcome: @unchecked Sendable {
        var finished = false
        var passed = false
        var summary = ""
        var jsonSummary = ""
    }
}
#endif
