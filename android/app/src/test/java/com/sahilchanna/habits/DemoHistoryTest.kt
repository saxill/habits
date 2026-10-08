package com.sahilchanna.habits

import com.sahilchanna.habits.data.InMemoryHabitsStore
import com.sahilchanna.habits.data.MemoryStorage
import com.sahilchanna.habits.data.Settings
import com.sahilchanna.habits.model.DemoHistory
import com.sahilchanna.habits.model.HabitsClock
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

/**
 * The demo-history fingerprint.
 *
 * The whole point of the sweep is that it removes the seeded rows and *nothing else*, so the tests
 * that matter are the near misses: a past day ticked by hand, a real completion on the same days.
 */
class DemoHistoryTest {

    private val clock: HabitsClock = T.clock("2026-03-10T12:00:00Z")
    private val seed = Instant.parse("2026-03-10T08:00:00Z")

    private fun seeded(day: String, completedAt: String, habitCreatedAt: String = "2026-03-10T08:00:00Z") =
        DemoHistory.isSeeded(
            T.day(day),
            Instant.parse(completedAt),
            Instant.parse(habitCreatedAt),
            seed,
            clock,
        )

    @Test
    fun `a backfilled day before the install day is seeded`() {
        assertTrue(seeded("2026-03-07", "2026-03-07T08:00:03Z"))
    }

    @Test
    fun `a completion on the install day itself is not seeded`() {
        // Same day, same stamp shape — but a real user's first tick, not backfill.
        assertFalse(seeded("2026-03-10", "2026-03-10T08:00:03Z"))
    }

    @Test
    fun `a past day ticked after the fact is kept`() {
        // The fingerprint's second half: the timestamp's own day must equal the day it is for.
        // Tapping "yesterday" from today stamps it today, so it never matches.
        assertFalse(seeded("2026-03-07", "2026-03-10T09:15:00Z"))
    }

    @Test
    fun `a completion on a habit created later is kept`() {
        assertFalse(seeded("2026-03-07", "2026-03-07T08:00:03Z", habitCreatedAt = "2026-03-20T09:00:00Z"))
    }

    @Test
    fun `the seed window has a little slack for a slow first launch`() {
        // 100s later than the seed: still the same seeding pass.
        assertTrue(seeded("2026-03-07", "2026-03-07T08:00:03Z", habitCreatedAt = "2026-03-10T08:01:40Z"))
        // 200s later: a different instant, so someone made this habit by hand.
        assertFalse(seeded("2026-03-07", "2026-03-07T08:00:03Z", habitCreatedAt = "2026-03-10T08:03:20Z"))
    }

    @Test
    fun `the sweep removes the seeded rows and leaves real ones`() = runTest {
        val store = InMemoryHabitsStore()
        val settings = Settings(MemoryStorage())
        settings.seeded = true

        val old = T.habit(id = "old", createdAt = seed)
        // Backfilled: dated before the install day, stamped on that same day.
        T.done(old, T.day("2026-03-07"), at = Instant.parse("2026-03-07T08:00:01Z"))
        T.done(old, T.day("2026-03-08"), at = Instant.parse("2026-03-08T08:00:01Z"))
        // Real: ticked today.
        T.done(old, T.day("2026-03-10"), at = Instant.parse("2026-03-10T09:30:00Z"))

        val graph = T.graph(listOf(old))
        store.upsertHabit(old)
        graph.completions.forEach { store.insertCompletion(it) }

        val removed = DemoHistory.removeIfNeeded(store, graph, settings, clock)
        assertEquals(2, removed)
        assertEquals(1, store.completions().size)
        assertEquals(T.day("2026-03-10"), store.completions().first().day)
    }

    @Test
    fun `the sweep runs once`() = runTest {
        val store = InMemoryHabitsStore()
        val settings = Settings(MemoryStorage())
        settings.seeded = true

        val old = T.habit(id = "old", createdAt = seed)
        T.done(old, T.day("2026-03-07"), at = Instant.parse("2026-03-07T08:00:01Z"))
        val graph = T.graph(listOf(old))
        store.upsertHabit(old)
        graph.completions.forEach { store.insertCompletion(it) }

        assertEquals(1, DemoHistory.removeIfNeeded(store, graph, settings, clock))
        // Second call finds the flag set: nothing removed, and nothing re-scanned.
        assertEquals(0, DemoHistory.removeIfNeeded(store, graph, settings, clock))
    }

    @Test
    fun `a store that was never seeded is left alone`() = runTest {
        val store = InMemoryHabitsStore()
        val settings = Settings(MemoryStorage())
        val habit = T.habit(id = "h", createdAt = seed)
        T.done(habit, T.day("2026-03-07"), at = Instant.parse("2026-03-07T08:00:01Z"))
        val graph = T.graph(listOf(habit))
        store.upsertHabit(habit)
        graph.completions.forEach { store.insertCompletion(it) }

        assertEquals(0, DemoHistory.removeIfNeeded(store, graph, settings, clock))
        assertEquals(1, store.completions().size)
    }
}
