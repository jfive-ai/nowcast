import Foundation
import os

/// Centralized `os.Logger` access — the app's structured logging layer.
///
/// Prefer these over `print` / `NSLog`: unified-logging output is structured,
/// filterable in Console.app / `log stream --predicate 'subsystem ==
/// "com.jfive-ai.nowcast"'`, persisted across launches, and privacy-aware.
///
/// **Secrets/PII:** interpolated dynamic strings default to `.private` (masked
/// in release). When you mark a value `.public` so it's readable in logs, run
/// it through `SecretRedactor` first (or use `Error.redactedDescription`) so an
/// API key or secret URL token can't leak into the system log.
enum Log {
    private static let subsystem = "com.jfive-ai.nowcast"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let storage = Logger(subsystem: subsystem, category: "storage")
    static let pipeline = Logger(subsystem: subsystem, category: "pipeline")
    static let network = Logger(subsystem: subsystem, category: "network")
    static let scheduler = Logger(subsystem: subsystem, category: "scheduler")
    static let delivery = Logger(subsystem: subsystem, category: "delivery")
    static let spotlight = Logger(subsystem: subsystem, category: "spotlight")
}
