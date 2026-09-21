import ActivityKit
import Foundation
import os
import SwiftUI

/// Bridges the app and the widget extension: one live activity per running timed habit,
/// rendered on the Dynamic Island + lock screen.
final class LiveActivityController: ObservableObject {
    static let shared = LiveActivityController()
    private static let log = Logger(subsystem: "com.sahil.habits.term", category: "LiveActivity")
    private var current: Activity<TimerActivityAttributes>?

    /// Last notable event, surfaced in Profile for on-device diagnosis.
    @Published var lastEvent = "no attempt yet"

    var systemEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }
    var runningCount: Int { Activity<TimerActivityAttributes>.activities.count }

    private func note(_ s: String) {
        lastEvent = s
        Self.log.info("\(s, privacy: .public)")
    }

    func start(habit: Habit, target: TimeInterval, retry: Int = 0) {
        guard UserDefaults.standard.object(forKey: SettingsKey.liveActivitiesEnabled) == nil
                || UserDefaults.standard.bool(forKey: SettingsKey.liveActivitiesEnabled) else {
            note("off in app settings — skipping")
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            note("BLOCKED: system permission denied")
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
            let msg = "started for \(habit.name)"
            note(msg)
        } catch {
            // At launch the resume loop fires before the app is fully foreground;
            // ActivityKit rejects with "Target is not foreground" — retry with backoff.
            if error.localizedDescription.contains("not foreground") && retry < 5 {
                Self.log.info("not foreground yet — retrying (\(retry + 1))")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    self.start(habit: habit, target: target, retry: retry + 1)
                }
            } else {
                let msg = "request failed: \(error.localizedDescription)"
                note(msg)
                Self.log.error("\(msg, privacy: .public)")
            }
        }
    }

    func stop(done: Bool) {
        current = nil
        // End all activities of this type, not just the handle we hold — after a
        // relaunch the original handle belongs to a dead process.
        let activities = Activity<TimerActivityAttributes>.activities
        guard !activities.isEmpty else { return }
        note("stopping \(activities.count) activity(ies)")
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