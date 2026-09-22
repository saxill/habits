import Foundation
import SwiftData
import WidgetKit
import ActivityKit

/// Builds the shared widget snapshot from the live SwiftData store and pushes it to
/// the app group, then asks WidgetKit to refresh. Called after every mutation and
/// whenever the app enters the background.
enum SnapshotPublisher {
    static func publish(context: ModelContext) {
        // Widget taps land here first, so the snapshot below reflects them.
        PendingToggleApplier.apply(context: context)

        let cal = Calendar.current
        let day = cal.startOfDay(for: Date())
        let routines = (try? context.fetch(
            FetchDescriptor<Routine>(sortBy: [SortDescriptor(\Routine.sortIndex)])
        )) ?? []

        var snapRoutines: [SnapshotRoutine] = []
        var done = 0
        var total = 0
        var allHabits: [Habit] = []

        for r in routines {
            allHabits.append(contentsOf: r.habits)
            var habits: [SnapshotHabit] = []
            for h in r.habits.sorted(by: { $0.sortIndex < $1.sortIndex }) {
                guard h.scheduleDays.contains(Streaks.weekdayIndex(day)) else { continue }
                let isDone = h.completion(on: day) != nil
                if isDone { done += 1 }
                total += 1
                habits.append(SnapshotHabit(
                    id: h.id,
                    name: h.name,
                    icon: h.icon,
                    colorHex: h.color.hex,
                    isTimed: h.type == .timed,
                    done: isDone,
                    streak: Streaks.habitStreak(h)
                ))
            }
            snapRoutines.append(SnapshotRoutine(
                id: r.id, name: r.name, subtitle: r.subtitle, icon: r.icon, habits: habits
            ))
        }

        let themeId = UserDefaults.standard.string(forKey: SettingsKey.themeId) ?? "ansi-dark"
        let theme = ThemeStore.shared.byId(themeId)

        // Every running timer, keyed by habit id — one live activity each. Several can run at
        // once, so the widget's single "running" line shows the most recently started one.
        let runningHabits = allHabits.filter { $0.startedAt != nil }
        var runningById: [String: LiveActivityController.RunningTimer] = [:]
        for h in runningHabits {
            runningById[h.id.uuidString] = LiveActivityController.RunningTimer(
                name: h.name,
                icon: h.icon,
                colorHex: h.color.hex,
                routineName: h.routine?.name ?? "",
                targetSeconds: h.targetSeconds,
                pausedAt: h.pausedAt,
                pausedSeconds: h.pausedSeconds
            )
        }

        var running: HabitsSnapshot.Running?
        if let h = runningHabits.max(by: { ($0.startedAt ?? .distantPast) < ($1.startedAt ?? .distantPast) }),
           let started = h.startedAt {
            running = HabitsSnapshot.Running(
                name: h.name, startedAt: started,
                targetSeconds: h.targetSeconds, colorHex: h.color.hex,
                pausedAt: h.pausedAt, pausedSeconds: h.pausedSeconds
            )
        }

        let streak = Streaks.overall(completions: allHabits.flatMap { $0.completions })

        HabitsSnapshot(
            day: day,
            generatedAt: Date(),
            routines: snapRoutines,
            doneCount: done,
            totalCount: total,
            streak: streak,
            background: theme.background,
            foreground: theme.foreground,
            comment: theme.comment,
            accent: theme.habitsAccent,
            running: running
        ).save()

        WidgetCenter.shared.reloadAllTimelines()

        // Keep every running activity's day context, pause state and display fields in step
        // with the store — each activity is a live view of its own timer, wherever it's
        // driven from. Activities whose habit stopped running get swept instead.
        LiveActivityController.shared.endOrphans(runningIds: Set(runningById.keys))
        LiveActivityController.shared.pushProgress(
            done: done, total: total, streak: streak, running: runningById
        )
        #if DEBUG
        HabitsDebugLog.append(
            "publish: \(done)/\(total) running=\(runningHabits.map(\.name).joined(separator: "+")) "
            + "paused=\(runningHabits.filter(\.isPaused).count) "
            + "activities=\(Activity<TimerActivityAttributes>.activities.count)"
        )
        #endif
    }
}
