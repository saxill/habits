import Foundation
import SwiftData
import UserNotifications

/// Handles reminder lock-screen actions. Both categories work the same way: "done"/"log glass"
/// records the completion straight into SwiftData and refreshes the widgets without bringing the
/// app UI up, and "in 1h" pushes the reminder back.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()

    func install() {
        WaterReminders.registerCategory()
        HabitReminders.registerCategory()
        UNUserNotificationCenter.current().delegate = self
    }

    /// Show reminders even while the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        let habitId = (info["habitId"] as? String).flatMap(UUID.init(uuidString:))

        switch response.actionIdentifier {
        case WaterReminders.logGlassAction:
            // An increment, not a tick: water is measured in glasses, and the day is usually
            // already done by the first one. `logCompletion` would no-op here.
            await WaterReminders.logGlass(habitId: habitId)
        case WaterReminders.snoozeAction:
            WaterReminders.snooze(habitId: habitId)

        case HabitReminders.doneAction:
            guard let habitId else { return }
            // The day the reminder was *for*, not the day it was tapped — actioning a 21:00
            // reminder from the lock screen at 00:30 should credit yesterday.
            let day = (info["day"] as? String)
                .flatMap(ISO8601DateFormatter().date(from:))
                ?? Calendar.current.startOfDay(for: Date())
            await logCompletion(habitId: habitId, day: Calendar.current.startOfDay(for: day))
        case HabitReminders.snoozeAction:
            HabitReminders.snooze(habitId: habitId, day: (info["day"] as? String)
                .flatMap(ISO8601DateFormatter().date(from:)))

        default:
            break // a plain tap opens the app on the habits tab
        }
    }

    /// Records a completion the same way the widgets do, then re-syncs so the reminder that was
    /// just actioned does not sit there scheduled for a habit that is already done.
    @MainActor
    private func logCompletion(habitId: UUID, day: Date) {
        guard let container = HabitsApp.sharedContainer else { return }
        PendingToggleQueue.set(habitId: habitId, day: day, done: true)
        // The main context, not a fresh one: a second context would take the write while
        // the UI kept republishing its stale copy over the top of it.
        SnapshotPublisher.publish(context: container.mainContext)
        HabitReminders.sync()
        WaterReminders.sync()
    }
}
