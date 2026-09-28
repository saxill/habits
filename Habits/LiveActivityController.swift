import ActivityKit
import Foundation
import os
import SwiftUI

/// Bridges the app and the widget extension: one live activity per running timed habit,
/// rendered on the Dynamic Island + lock screen.
///
/// Deliberately keyed by habit rather than holding a single handle. Every row in the app
/// renders its own running timer, and `TimerActivityAttributes.habitId` exists so a button
/// knows which habit it belongs to — so N running timers means N activities. Holding one
/// meant starting a second timer silently ended the first timer's activity while its clock
/// kept running, leaving it invisible.
final class LiveActivityController: ObservableObject {
    static let shared = LiveActivityController()
    private static let log = Logger(subsystem: "com.sahil.habits.term", category: "LiveActivity")
    private var current: [String: Activity<TimerActivityAttributes>] = [:]

    /// Last notable event, surfaced in Profile for on-device diagnosis.
    @Published var lastEvent = "no attempt yet"

    var systemEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }
    var runningCount: Int { Activity<TimerActivityAttributes>.activities.count }

    private func note(_ s: String) {
        lastEvent = s
        Self.log.info("\(s, privacy: .public)")
    }

    /// This habit's activities, live or orphaned by a previous app process.
    private func activities(for habitId: String) -> [Activity<TimerActivityAttributes>] {
        Activity<TimerActivityAttributes>.activities.filter { $0.attributes.habitId == habitId }
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
        let id = habit.id.uuidString
        // End this habit's own leftovers (a previous process, or a restart) — and only
        // this habit's: other running timers keep their activities.
        for stale in activities(for: id) {
            let state = stale.content.state
            Task {
                await stale.end(
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
        current[id] = nil
        let attributes = TimerActivityAttributes(
            habitName: habit.name,
            habitIcon: habit.icon,
            colorHex: habit.color.hex,
            habitId: id,
            routineName: habit.routine?.name ?? ""
        )
        let d = UserDefaults.standard
        let state = TimerActivityAttributes.ContentState(
            startDate: habit.startedAt ?? Date(),
            targetSeconds: target,
            isDone: false,
            pausedAt: habit.pausedAt,
            pausedSeconds: habit.pausedSeconds,
            showTimer: d.object(forKey: SettingsKey.laShowTimer) == nil || d.bool(forKey: SettingsKey.laShowTimer),
            showProgress: d.object(forKey: SettingsKey.laShowProgress) == nil || d.bool(forKey: SettingsKey.laShowProgress),
            showName: d.object(forKey: SettingsKey.laShowName) == nil || d.bool(forKey: SettingsKey.laShowName),
            countDown: d.object(forKey: SettingsKey.laCountDown) == nil || d.bool(forKey: SettingsKey.laCountDown),
            liveName: habit.name,
            liveIcon: habit.icon,
            liveColorHex: habit.color.hex,
            liveRoutineName: habit.routine?.name ?? ""
        )
        do {
            current[id] = try Activity.request(
                attributes: attributes,
                // Once well past the target the content is no longer "live" — let the
                // system mark it stale rather than showing a timer that stalled.
                content: ActivityContent(
                    state: state,
                    staleDate: state.startDate.addingTimeInterval(max(target, 300) + 300)
                )
            )
            note("started for \(habit.name)")
        } catch {
            // At launch the resume loop fires before the app is fully foreground;
            // ActivityKit rejects with "Target is not foreground" — retry with backoff.
            if error.localizedDescription.contains("not foreground") && retry < 5 {
                Self.log.info("not foreground yet — retrying (\(retry + 1))")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    self.start(habit: habit, target: target, retry: retry + 1)
                }
            } else {
                let msg = "request failed for \(habit.name): \(error.localizedDescription)"
                note(msg)
                Self.log.error("\(msg, privacy: .public)")
            }
        }
    }

    /// Pushes today's progress into every running activity, so each island/lock screen shows
    /// live `[4/7]` context instead of only what was true when its timer started.
    ///
    /// Each activity gets *its own* habit's pause state and display fields — `running` is
    /// keyed by habit id — so one timer pausing never disturbs another's countdown.
    /// Display fields live here rather than only in the attributes because attributes are
    /// immutable for the activity's life: renaming or recoloring a habit mid-timer would
    /// otherwise keep showing the old values.
    func pushProgress(done: Int, total: Int, streak: Int, running: [String: RunningTimer]) {
        let activities = Activity<TimerActivityAttributes>.activities
        guard !activities.isEmpty else { return }
        Task {
            for activity in activities {
                guard let timer = running[activity.attributes.habitId] else { continue }
                var state = activity.content.state
                guard state.doneToday != done || state.totalToday != total || state.streak != streak
                        || state.pausedAt != timer.pausedAt || state.pausedSeconds != timer.pausedSeconds
                        || state.liveName != timer.name || state.liveIcon != timer.icon
                        || state.liveColorHex != timer.colorHex || state.liveRoutineName != timer.routineName
                        || state.targetSeconds != timer.targetSeconds
                else { continue }
                state.doneToday = done
                state.totalToday = total
                state.streak = streak
                state.pausedAt = timer.pausedAt
                state.pausedSeconds = timer.pausedSeconds
                state.liveName = timer.name
                state.liveIcon = timer.icon
                state.liveColorHex = timer.colorHex
                state.liveRoutineName = timer.routineName
                state.targetSeconds = timer.targetSeconds
                #if DEBUG
                HabitsDebugLog.append(
                    "push: \(timer.name) paused=\(timer.pausedAt != nil) target=\(Int(timer.targetSeconds))s"
                )
                #endif
                await activity.update(ActivityContent(
                    state: state,
                    staleDate: state.startDate.addingTimeInterval(max(state.targetSeconds, 300) + 300)
                ))
            }
        }
    }

    /// A running timer, as the live activity needs to see it.
    struct RunningTimer {
        var name: String
        var icon: String
        var colorHex: String
        var routineName: String
        var targetSeconds: TimeInterval
        var pausedAt: Date?
        var pausedSeconds: TimeInterval
    }

    /// Safety net: end any activity whose habit is no longer running (the app was force-quit,
    /// or the extension ended one we didn't see) rather than leaving a dead pill behind.
    /// Activities belonging to *other* running timers are left alone.
    /// Skipped briefly after a deliberate end, so a finished timer keeps its completion card.
    ///
    /// **Ordering contract:** anything that clears a habit's `startedAt` must stamp
    /// `LiveActivityGrace` (or end the activity itself) *before* the next publish runs. This
    /// sweep runs on every publish and finds nothing running by definition once a timer has
    /// been logged, so a publish that lands first ends the activity with `.immediate` and the
    /// completion card never appears.
    func endOrphans(runningIds: Set<String>) {
        guard LiveActivityGrace.sweepAllowed else { return }
        let orphans = Activity<TimerActivityAttributes>.activities.filter {
            !runningIds.contains($0.attributes.habitId)
        }
        guard !orphans.isEmpty else { return }
        note("clearing \(orphans.count) orphaned activity(ies)")
        Task {
            for activity in orphans {
                var state = activity.content.state
                state.isDone = false
                await activity.end(
                    ActivityContent(state: state, staleDate: nil),
                    dismissalPolicy: .immediate
                )
            }
        }
    }

    /// Ends one habit's timer activity. Only that habit's: another running timer keeps its own.
    /// `habitId` nil ends every activity, which is only right for a full teardown (the
    /// app-wide live-activity switch being turned off).
    func stop(habitId: UUID? = nil, done: Bool) {
        if let habitId {
            current[habitId.uuidString] = nil
        } else {
            current.removeAll()
        }
        let activities = Activity<TimerActivityAttributes>.activities.filter {
            habitId == nil || $0.attributes.habitId == habitId!.uuidString
        }
        guard !activities.isEmpty else { return }
        note("stopping \(activities.count) activity(ies)")
        LiveActivityGrace.suppressSweep(
            for: done ? LiveActivityGrace.doneGrace : LiveActivityGrace.discardGrace)
        Task {
            for activity in activities {
                // Mutate the live state rather than rebuilding it: the day counts, streak and
                // display prefs it carries are what the completion card renders from.
                var state = activity.content.state
                // Stamp the real time spent BEFORE clearing the pause state: logging while
                // paused must not bill the ongoing pause as work.
                let ongoingPause = state.pausedAt.map { max(0, Date().timeIntervalSince($0)) } ?? 0
                state.isDone = done
                state.pausedAt = nil
                if done {
                    state.loggedSeconds = max(0, Date().timeIntervalSince(state.startDate) - state.pausedSeconds - ongoingPause)
                }
                await activity.end(
                    ActivityContent(state: state, staleDate: nil),
                    // a finished timer lingers on the completion card; a cancel clears at once
                    dismissalPolicy: done
                        ? .after(Date().addingTimeInterval(LiveActivityGrace.doneLinger))
                        : .immediate
                )
            }
        }
    }
}
