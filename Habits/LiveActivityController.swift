import ActivityKit
import Foundation
import os

/// Bridges the app and the widget extension: one live activity per running timed habit,
/// rendered on the Dynamic Island + lock screen.
final class LiveActivityController {
    static let shared = LiveActivityController()
    private static let log = Logger(subsystem: "com.sahil.habits.term", category: "LiveActivity")
    private var current: Activity<TimerActivityAttributes>?

    func start(habit: Habit, target: TimeInterval) {
        guard UserDefaults.standard.object(forKey: SettingsKey.liveActivitiesEnabled) == nil
                || UserDefaults.standard.bool(forKey: SettingsKey.liveActivitiesEnabled) else {
            Self.log.info("disabled in settings — skipping")
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            Self.log.error("activities disabled by system")
            return
        }
        // End every live activity of this type — including ones orphaned by a previous
        // app process, whose handles we no longer hold.
        for orphan in Activity<TimerActivityAttributes>.activities {
            let state = orphan.content.state
            Task {
                await orphan.end(
                    ActivityContent(
                        state: TimerActivityAttributes.ContentState(
                            startDate: state.startDate,
                            targetSeconds: state.targetSeconds,
                            isDone: false
                        ),
                        staleDate: nil
                    ),
                    dismissalPolicy: .immediate
                )
            }
        }
        current = nil
        let attributes = TimerActivityAttributes(
            habitName: habit.name,
            emoji: "⏱",
            colorHex: habit.color.hex
        )
        let d = UserDefaults.standard
        let state = TimerActivityAttributes.ContentState(
            startDate: Date(),
            targetSeconds: target,
            isDone: false,
            showTimer: d.object(forKey: SettingsKey.laShowTimer) == nil || d.bool(forKey: SettingsKey.laShowTimer),
            showProgress: d.object(forKey: SettingsKey.laShowProgress) == nil || d.bool(forKey: SettingsKey.laShowProgress),
            showName: d.object(forKey: SettingsKey.laShowName) == nil || d.bool(forKey: SettingsKey.laShowName)
        )
        do {
            current = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil)
            )
            Self.log.info("started for \(habit.name, privacy: .public)")
        } catch {
            Self.log.error("request failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop(done: Bool) {
        current = nil
        // End all activities of this type, not just the handle we hold — after a
        // relaunch the original handle belongs to a dead process.
        let activities = Activity<TimerActivityAttributes>.activities
        guard !activities.isEmpty else { return }
        Task {
            for activity in activities {
                let state = activity.content.state
                await activity.end(
                    ActivityContent(
                        state: TimerActivityAttributes.ContentState(
                            startDate: state.startDate,
                            targetSeconds: state.targetSeconds,
                            isDone: done
                        ),
                        staleDate: nil
                    ),
                    dismissalPolicy: .immediate
                )
            }
        }
    }
}