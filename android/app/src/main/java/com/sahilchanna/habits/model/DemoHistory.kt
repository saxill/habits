package com.sahilchanna.habits.model

import com.sahilchanna.habits.data.HabitsGraph
import com.sahilchanna.habits.data.HabitsStore
import com.sahilchanna.habits.data.Settings
import java.time.Instant
import java.time.LocalDate

/**
 * The fake history an earlier first launch backfilled, and its removal.
 *
 * The iOS build seeded nine days of made-up completions before the install day so stats looked
 * alive on first open. They look real everywhere — stats, streaks, achievements, XP — so they have
 * to go, and only they may go. Android never shipped that seed, but an install restored from an iOS
 * backup (or from a build of this port that did seed) can still carry the rows, so the sweep exists
 * here too and is exercised by the same tests.
 *
 * A seeded completion has a fingerprint no real one can: it belongs to a habit the seed created,
 * it's dated *before* the install day, and its timestamp falls on that same day. A tick you make is
 * stamped with the moment you tapped, so even a past day you ticked afterwards (tapped today, for
 * yesterday) carries a later stamp and is kept.
 */
object DemoHistory {
    /** Seeded habits are all created in the same instant; allow a little slack. */
    const val SEED_WINDOW_SECONDS: Long = 120

    fun isSeeded(
        day: LocalDate,
        completedAt: Instant,
        habitCreatedAt: Instant,
        seedCreatedAt: Instant,
        clock: HabitsClock,
    ): Boolean {
        val withinSeed = kotlin.math.abs(habitCreatedAt.epochSecond - seedCreatedAt.epochSecond) <= SEED_WINDOW_SECONDS
        return withinSeed &&
            day < clock.dayOf(seedCreatedAt) &&
            clock.dayOf(completedAt) == day
    }

    /** Removes the seeded completions once. Returns how many went. */
    suspend fun removeIfNeeded(store: HabitsStore, graph: HabitsGraph, settings: Settings, clock: HabitsClock): Int {
        if (!settings.seeded || settings.demoHistoryRemoved) return 0
        settings.demoHistoryRemoved = true

        // The seed created every habit it made in one go, before anything else existed.
        val seedCreatedAt = graph.habits.minOfOrNull { it.createdAt } ?: return 0

        val seeded = graph.completions.filter { completion ->
            val habit = completion.habit ?: return@filter false
            isSeeded(completion.day, completion.completedAt, habit.createdAt, seedCreatedAt, clock)
        }
        seeded.forEach { store.deleteCompletion(it.id) }
        return seeded.size
    }
}
