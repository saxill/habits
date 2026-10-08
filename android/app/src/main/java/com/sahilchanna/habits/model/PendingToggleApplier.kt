package com.sahilchanna.habits.model

import com.sahilchanna.habits.data.Completion
import com.sahilchanna.habits.data.Habit
import com.sahilchanna.habits.data.HabitsGraph
import com.sahilchanna.habits.data.HabitsStore
import java.time.Instant
import java.time.LocalDate

/**
 * Folds widget- and notification-originated toggles into the store. Runs before every snapshot
 * publish, so the app's own UI — and the next authoritative snapshot — reflect the tap.
 */
class PendingToggleApplier(
    private val store: HabitsStore,
    private val clock: HabitsClock,
) {
    /** Returns true when anything in the store changed. */
    suspend fun apply(graph: HabitsGraph, queue: PendingToggleQueue): Boolean {
        val pending = queue.drain()
        if (pending.isEmpty()) return false

        val now = clock.now()
        val today = clock.today()
        var changed = false

        for (p in pending) {
            val habit = graph.habit(p.habitId) ?: continue
            // The queued day is already a completion day (the queue derives it from the clock's
            // reset rule), so it is used as-is rather than re-derived from a midnight instant —
            // re-deriving would push a queued day back a day once the reset hour is past midnight.
            val day = p.day

            // pause/resume from the timer notification: clock stops, session stays open. The queue
            // can hand this branch an entry that *also* carries a tick or a glass (the queue merges
            // rather than replaces), so it no longer claims the whole entry.
            val pause = p.pause
            if (pause != null) {
                val was = habit.isPaused
                if (pause) habit.pauseTimer(now) else habit.resumeTimer(now)
                if (habit.isPaused != was) changed = true
                // Persisted here rather than at the end of the loop: an entry can carry a pause
                // *and* a glass, and the glass branch below leaves the loop early.
                store.upsertHabit(habit)
            }

            // "discard": stop the timer, record nothing.
            if (p.stopTimer) {
                if (habit.startedAt != null) {
                    habit.clearTimer()
                    store.upsertHabit(habit)
                    changed = true
                }
                continue
            }

            // A glass of water: an increment, not a state. Handled before `done` because the day is
            // usually *already* ticked off by the first glass, and `done` is a no-op then — which is
            // how "log glass" used to silently do nothing on every tap after the first.
            val glasses = p.glasses
            if (glasses != null) {
                val existing = habit.completion(day)
                if (existing != null) {
                    existing.value += glasses.toDouble()
                    store.upsertCompletion(existing)
                } else {
                    // The first glass is what makes the day count as done; the tally rides along in
                    // `value` without changing what "done" means to streaks or achievements.
                    val created = Completion.of(habit.id, day, now, glasses.toDouble(), source = "widget")
                    created.habit = habit
                    habit.completions.add(created)
                    store.insertCompletion(created)
                }
                changed = true
                continue
            }

            if (p.done) {
                // Past days can be corrected, never completed: a tick is stamped with the moment it
                // was made, so one placed on yesterday would read as "done that day" while being a
                // lie. Same rule the habit row enforces in-app.
                if (day != today) continue

                if (habit.type == HabitType.TIMED && habit.startedAt != null) {
                    // Mirrors the habit row's toggle: checking a running timer records the elapsed
                    // time, pauses excluded.
                    val elapsed = habit.elapsedSeconds(now)
                    habit.clearTimer()
                    val created = Completion.of(habit.id, day, now, elapsed.toDouble(), source = "widget")
                    created.habit = habit
                    habit.completions.add(created)
                    store.insertCompletion(created)
                    store.upsertHabit(habit)
                    changed = true
                } else if (habit.completion(day) == null) {
                    val created = Completion.of(habit.id, day, now, 1.0, source = "widget")
                    created.habit = habit
                    habit.completions.add(created)
                    store.insertCompletion(created)
                    changed = true
                }
            } else if (p.pause == null) {
                // An explicit un-tick. A pause-only entry carries `done == false` because it must say
                // *something* — it must not un-tick the day it arrived on.
                val existing = habit.completion(day)
                if (existing != null) {
                    store.deleteCompletion(existing.id)
                    habit.completions.removeAll { it.id == existing.id }
                    // The timer belongs to the day it was started on (DayReset's rule): un-ticking a
                    // past day must not stop today's run.
                    val started = habit.startedAt
                    if (started != null && clock.dayOf(started) == day) {
                        habit.clearTimer()
                        store.upsertHabit(habit)
                    }
                    changed = true
                }
            }
        }

        return changed
    }
}

/** Logging a glass from the app UI (the `[+]` on a water row) — the same write the queue makes. */
suspend fun logGlassNow(store: HabitsStore, habit: Habit, day: LocalDate, now: Instant, count: Int = 1) {
    val existing = habit.completion(day)
    if (existing != null) {
        existing.value += count.toDouble()
        store.upsertCompletion(existing)
    } else {
        val created = Completion.of(habit.id, day, now, count.toDouble())
        created.habit = habit
        habit.completions.add(created)
        store.insertCompletion(created)
    }
}
