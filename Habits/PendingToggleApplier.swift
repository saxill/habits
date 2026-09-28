import Foundation
import SwiftData

/// Folds widget-originated toggles into SwiftData. Runs before every snapshot publish, so
/// the app's own UI — and the next authoritative snapshot — reflect the widget tap.
enum PendingToggleApplier {
    /// Diagnostic channel readable from the app group (no console access needed on device).
    private static func note(_ s: String) {
        #if DEBUG
        HabitsDebugLog.append("apply: \(s)")
        #endif
    }

    @discardableResult
    static func apply(context: ModelContext) -> Bool {
        let pending = PendingToggleQueue.drain()
        #if DEBUG
        HabitsDebugLog.append("apply: called, pending=\(pending.count)")
        #endif
        guard !pending.isEmpty else { return false }
        let habits = (try? context.fetch(FetchDescriptor<Habit>())) ?? []
        let cal = Calendar.current
        var changed = false
        var missing: [String] = []

        for p in pending {
            guard let habit = habits.first(where: { $0.id == p.habitId }) else {
                missing.append(p.habitId.uuidString)
                continue
            }
            let day = cal.startOfDay(for: p.day)

            // pause/resume from the live activity: clock stops, session stays open. The queue
            // can hand this branch an entry that *also* carries a tick or a glass (the queue
            // merges rather than replaces), so it no longer claims the whole entry.
            if let pause = p.pause {
                let was = habit.isPaused
                pause ? habit.pauseTimer() : habit.resumeTimer()
                if habit.isPaused != was {
                    changed = true
                    note("\(habit.name): \(pause ? "paused" : "resumed") at \(Int(habit.elapsedSeconds()))s elapsed")
                }
            }

            // "discard" from the live activity: stop the timer, record nothing
            if p.stopTimer {
                if habit.startedAt != nil {
                    habit.clearTimer()
                    changed = true
                    note("\(habit.name): timer stopped (no completion)")
                }
                continue
            }

            // A glass of water: an increment, not a state. Handled before `done` because the day
            // is usually *already* ticked off by the first glass, and `done` is a no-op then —
            // which is how "log glass" used to silently do nothing on every tap after the first.
            if let glasses = p.glasses {
                if let existing = habit.completion(on: day) {
                    existing.value += Double(glasses)
                } else {
                    // The first glass is what makes the day count as done; the tally rides along
                    // in `value` without changing what "done" means to streaks or achievements.
                    let c = Completion(day: day, completedAt: Date(), value: Double(glasses))
                    c.habit = habit
                    context.insert(c)
                }
                changed = true
                note("\(habit.name): +\(glasses) glass → \(Int(habit.completion(on: day)?.value ?? 0)) today")
                continue
            }

            if p.done {
                // Mirrors HabitRow.toggle: checking a running timer records the elapsed time.
                if habit.type == .timed, habit.startedAt != nil, cal.isDate(day, inSameDayAs: Date()) {
                    // Pauses don't count toward the logged value.
                    let elapsed = habit.elapsedSeconds()
                    habit.clearTimer()
                    let c = Completion(day: day, completedAt: Date(), value: elapsed)
                    c.habit = habit
                    context.insert(c)
                    changed = true
                    note("\(habit.name): timed branch, \(Int(elapsed))s recorded")
                } else if habit.completion(on: day) == nil {
                    let c = Completion(day: day, completedAt: Date(), value: 1)
                    c.habit = habit
                    context.insert(c)
                    changed = true
                    note("\(habit.name): marked done (plain), startedAt=\(habit.startedAt == nil ? "nil" : "set")")
                } else {
                    note("\(habit.name): already done, no-op")
                }
            } else if p.pause == nil, let existing = habit.completion(on: day) {
                // An explicit un-tick. A pause-only entry carries `done == false` because it
                // must say *something* — it must not un-tick the day it arrived on.
                context.delete(existing)
                habit.completions.removeAll { $0 == existing }
                // The timer belongs to the day it was started on (DayReset's rule): un-ticking
                // a past day must not stop today's run.
                if let started = habit.startedAt, cal.isDate(started, inSameDayAs: day) {
                    habit.clearTimer()
                }
                changed = true
            }
        }

        if changed {
            do {
                try context.save()
                note("applied \(pending.count) pending, saved ok")
            } catch {
                note("SAVE FAILED: \(error)")
            }
        } else if !missing.isEmpty {
            note("no habit matched \(missing.joined(separator: ","))")
        }
        return changed
    }
}
