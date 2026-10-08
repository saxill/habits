import Foundation
import SwiftData

/// Clearing a day.
///
/// The only thing in this app that destroys real history, which is why it is written to be
/// undone: `reset` hands back exactly what it removed, in a form `restore` can put back, and the
/// caller keeps that receipt long enough to offer an undo. A destructive control on a phone that
/// cannot be taken back is not worth having — and the moment you want a reset is the moment you
/// mis-tapped something, which is exactly the moment you are most likely to mis-tap this too.
enum DayReset {
    /// One completion, lifted out of the store and held in memory.
    ///
    /// A plain value rather than the `Completion` itself: once the row is deleted its `habit` link
    /// is gone, so a reference kept for the undo would come back with nothing to attach to.
    struct Dropped: Equatable {
        let habitId: UUID
        let day: Date
        let value: Double
        let completedAt: Date
    }

    /// Deletes every completion on `day` and stops any timer started on it.
    ///
    /// Store-only — the caller is responsible for republishing the widget snapshot and re-syncing
    /// the reminders, which is what `resetToday` wraps up. Kept apart so the arithmetic can be
    /// tested without the notification centre in the room.
    @discardableResult
    static func reset(day: Date, context: ModelContext,
                      calendar: Calendar = .current) -> [Dropped] {
        let start = calendar.startOfDay(for: day)
        let habits = (try? context.fetch(FetchDescriptor<Habit>())) ?? []
        var dropped: [Dropped] = []

        for habit in habits {
            // Walked habit by habit rather than over every completion in the store: the day
            // filter then only ever sees the handful of rows that can match, and the habit is
            // already in hand for the receipt.
            guard let completion = habit.completion(on: start, calendar: calendar) else { continue }
            dropped.append(Dropped(habitId: habit.id, day: completion.day, value: completion.value,
                                   completedAt: completion.completedAt))
            context.delete(completion)
            habit.completions.removeAll { $0 == completion }
        }

        for habit in habits {
            // A timer belongs to the day it was started on, so one still running from an earlier
            // day is not this day's to clear.
            guard let started = habit.startedAt,
                  calendar.isDate(started, inSameDayAs: start) else { continue }
            habit.clearTimer()
        }

        try? context.save()

        #if DEBUG
        for d in dropped {
            let name = habits.first { $0.id == d.habitId }?.name ?? "?"
            HabitsDebugLog.append("reset-drop \(name) value=\(d.value) at=\(d.completedAt)")
        }
        #endif

        return dropped
    }

    /// Puts back exactly what `reset` took, and nothing else.
    ///
    /// A running timer does not come back to life: the seconds it had logged are restored and the
    /// day counts as done, but the clock is not restarted. That is the one thing an undo here
    /// does not fully reverse.
    static func restore(_ dropped: [Dropped], context: ModelContext,
                        calendar: Calendar = .current) {
        let habits = (try? context.fetch(FetchDescriptor<Habit>())) ?? []
        for d in dropped {
            guard let habit = habits.first(where: { $0.id == d.habitId }) else { continue }
            // Never a second completion on a day that already has one: one-per-habit-per-day is
            // the invariant every streak, stat and achievement here is built on. If something
            // was logged again while the undo was on screen, the newer value stands.
            guard habit.completion(on: d.day, calendar: calendar) == nil else { continue }
            let completion = Completion(day: d.day, completedAt: d.completedAt, value: d.value)
            completion.habit = habit
            context.insert(completion)
        }
        try? context.save()
    }

    /// The whole operation, with the app-wide consequences that have to follow it.
    @discardableResult
    static func resetToday(context: ModelContext) -> [Dropped] {
        let dropped = reset(day: Date(), context: context)
        finish(context: context)
        return dropped
    }

    static func restoreAll(_ dropped: [Dropped], context: ModelContext) {
        restore(dropped, context: context)
        finish(context: context)
    }

    /// What has to happen after the store changes: the widgets' copy of the day, and both
    /// reminder schedulers — which decide what to send from what is *not* done, so a day cleared
    /// at dinner time means this evening's nudges are due again.
    private static func finish(context: ModelContext) {
        SnapshotPublisher.publish(context: context)
        HabitReminders.sync()
        WaterReminders.sync()
    }
}
