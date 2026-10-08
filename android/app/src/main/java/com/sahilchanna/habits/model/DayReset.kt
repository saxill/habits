package com.sahilchanna.habits.model

import com.sahilchanna.habits.data.Completion
import com.sahilchanna.habits.data.HabitsGraph
import com.sahilchanna.habits.data.HabitsStore
import java.time.Instant
import java.time.LocalDate

/**
 * Clearing a day.
 *
 * The only thing in this app that destroys real history, which is why it is written to be undone:
 * `reset` hands back exactly what it removed, in a form `restore` can put back, and the caller
 * keeps that receipt long enough to offer an undo. A destructive control on a phone that cannot be
 * taken back is not worth having — and the moment you want a reset is the moment you mis-tapped
 * something, which is exactly the moment you are most likely to mis-tap this too.
 */
object DayReset {

    /**
     * One completion, lifted out of the store and held in memory.
     *
     * A plain value rather than the row itself: once the row is deleted its habit link is gone, so a
     * reference kept for the undo would come back with nothing to attach to.
     */
    data class Dropped(
        val habitId: String,
        val day: LocalDate,
        val value: Double,
        val completedAt: Instant,
    )

    /**
     * Deletes every completion on `day` and stops any timer started on it.
     *
     * Store-only — the caller is responsible for republishing the widget snapshot and re-syncing the
     * reminders, which is what the repository's `resetToday` wraps up. Kept apart so the arithmetic
     * can be tested without a notification manager in the room.
     */
    suspend fun reset(store: HabitsStore, graph: HabitsGraph, day: LocalDate, clock: HabitsClock): List<Dropped> {
        val dropped = mutableListOf<Dropped>()

        for (habit in graph.habits) {
            // Walked habit by habit rather than over every completion in the store: the day filter
            // then only ever sees the handful of rows that can match, and the habit is already in
            // hand for the receipt.
            val completion = habit.completion(day) ?: continue
            dropped.add(Dropped(habit.id, completion.day, completion.value, completion.completedAt))
            store.deleteCompletion(completion.id)
            habit.completions.removeAll { it.id == completion.id }
        }

        for (habit in graph.habits) {
            // A timer belongs to the day it was started on, so one still running from an earlier day
            // is not this day's to clear.
            val started = habit.startedAt ?: continue
            if (clock.dayOf(started) != day) continue
            habit.clearTimer()
            store.upsertHabit(habit)
        }

        return dropped
    }

    /**
     * Puts back exactly what `reset` took, and nothing else.
     *
     * A running timer does not come back to life: the seconds it had logged are restored and the day
     * counts as done, but the clock is not restarted. That is the one thing an undo here does not
     * fully reverse.
     */
    suspend fun restore(store: HabitsStore, graph: HabitsGraph, dropped: List<Dropped>) {
        for (d in dropped) {
            val habit = graph.habit(d.habitId) ?: continue
            // Never a second completion on a day that already has one: one-per-habit-per-day is the
            // invariant every streak, stat and achievement here is built on. If something was logged
            // again while the undo was on screen, the newer value stands.
            if (habit.completion(d.day) != null) continue
            val created = Completion.of(habit.id, d.day, d.completedAt, d.value, source = "undo")
            created.habit = habit
            habit.completions.add(created)
            store.insertCompletion(created)
        }
    }
}
