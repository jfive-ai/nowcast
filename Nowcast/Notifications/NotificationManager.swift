import Foundation
import UserNotifications
import AppKit

/// Wraps `UNUserNotificationCenter`. Posts a notification when a report
/// finishes and routes a tap back to the app so the report can be opened.
@MainActor
final class NotificationManager: NSObject {
    static let shared = NotificationManager()

    /// Set by `AppState` so a notification tap can reach app state.
    var onTapReport: ((UUID) -> Void)?

    /// Tracks whether we've successfully requested authorization. We don't
    /// crash if the user said no — we just stop posting.
    private(set) var isAuthorized: Bool = false

    nonisolated private static let reportIDKey = "nowcast.reportID"

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    /// Ask for permission. Safe to call repeatedly; the system caches the answer.
    func requestAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
        } catch {
            isAuthorized = false
        }
    }

    /// Post a notification for a freshly generated report.
    func postReportReady(_ report: Report) async {
        guard isAuthorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "Nowcast: \(report.topic)"
        content.body = "\(report.sourceCount) item\(report.sourceCount == 1 ? "" : "s") · \(report.window.displayName)"
        content.sound = .default
        content.userInfo = [Self.reportIDKey: report.id.uuidString]

        let request = UNNotificationRequest(
            identifier: report.id.uuidString,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    /// Show the banner even when the app is foregrounded.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// Tap handler — open the main window and forward the report id.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let idString = userInfo[Self.reportIDKey] as? String
        let reportID = idString.flatMap(UUID.init(uuidString:))
        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows where window.canBecomeMain {
                window.makeKeyAndOrderFront(nil)
                break
            }
            if let reportID {
                Self.shared.onTapReport?(reportID)
            }
            completionHandler()
        }
    }
}
