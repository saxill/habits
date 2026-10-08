package com.sahilchanna.habits

import com.sahilchanna.habits.data.InMemoryHabitsStore
import com.sahilchanna.habits.model.DayReset
import com.sahilchanna.habits.model.HabitsClock
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

/** The reset receipt and its undo — the one path in the app that destroys history. */
class DayResetTest {

    private val clock: HabitsClock = T.clock("2026-03-10T12:00:00Z")
    private val today = T.day("2026-03-10")
    private val yesterday = T.day("2026-03-09")

    @Test
    fun `reset clears the day and hands back what it took`() = runTest {
        val store = InMemoryHabitsStore()
        val a = T.habit(id = "a")
        val b = T.habit(id = "b")
        T.done(a, today)
        T.done(b, today)
        T.done(b, yesterday)

        val graph = T.graph(listOf(a, b))
        val dropped = DayReset.reset(store, graph, today, clock)

        assertEquals(2, dropped.size)
        assertNull(a.completion(today))
        assertNull(b.completion(today))
        // Yesterday is not this day's to clear.
        assertNotNull(b.completion(yesterday))
    }

    @Test
    fun `restore puts back exactly what reset took`() = runTest {
        val store = InMemoryHabitsStore()
        val a = T.habit(id = "a")
        T.done(a, today, value = 1.0)
        val graph = T.graph(listOf(a))

        val dropped = DayReset.reset(store, graph, today, clock)
        DayReset.restore(store, graph, dropped)

        val restored = a.completion(today)
        assertNotNull(restored)
        assertEquals(1.0, restored!!.value, 0.0001)
        assertEquals(1, store.completions().size)
    }

    @Test
    fun `restore never doubles up on a day since re-completed`() = runTest {
        val store = InMemoryHabitsStore()
        val a = T.habit(id = "a")
        T.done(a, today)
        val graph = T.graph(listOf(a))

        val dropped = DayReset.reset(store, graph, today, clock)
        // The user ticked it again while the undo was still on screen.
        T.done(a, today, value = 5.0)
        store.insertCompletion(a.completions.last())

        DayReset.restore(store, graph, dropped)
        assertEquals(1, a.completions.count { it.day == today })
        assertEquals(5.0, a.completion(today)!!.value, 0.0001)
    }

    @Test
    fun `reset stops a timer started today but leaves an older one running`() = runTest {
        val store = InMemoryHabitsStore()
        val running = T.habit(id = "running")
        running.startTimer(T.atDay("2026-03-10", hour = 9))
        val stale = T.habit(id = "stale")
        stale.startTimer(T.atDay("2026-03-08", hour = 9))
        val graph = T.graph(listOf(running, stale))

        DayReset.reset(store, graph, today, clock)

        assertNull(running.startedAt)
        assertNotNull(stale.startedAt)
    }

    @Test
    fun `a dropped completion carries the value it had`() = runTest {
        val store = InMemoryHabitsStore()
        val water = T.habit(id = "water")
        T.done(water, today, value = 5.0)
        val graph = T.graph(listOf(water))

        val dropped = DayReset.reset(store, graph, today, clock)
        assertEquals(1, dropped.size)
        assertEquals(5.0, dropped.first().value, 0.0001)
        assertEquals(today, dropped.first().day)
        assertTrue(dropped.first().habitId == "water")
    }

    @Test
    fun `restore ignores a habit that no longer exists`() = runTest {
        val store = InMemoryHabitsStore()
        val a = T.habit(id = "a")
        T.done(a, today)
        val graph = T.graph(listOf(a))
        val dropped = DayReset.reset(store, graph, today, clock)

        // The habit was deleted before the undo was used.
        val empty = T.graph(emptyList())
        DayReset.restore(store, empty, dropped)
        assertTrue(store.completions().isEmpty())
    }

    @Test
    fun `undo is a no-op for an empty receipt`() = runTest {
        val store = InMemoryHabitsStore()
        val graph = T.graph(emptyList())
        DayReset.restore(store, graph, emptyList())
        assertTrue(store.completions().isEmpty())
    }

    @Test
    fun `reset reports a dropped timestamp so the undo keeps the original`() = runTest {
        val store = InMemoryHabitsStore()
        val a = T.habit(id = "a")
        val stamp = Instant.parse("2026-03-10T07:30:00Z")
        T.done(a, today, at = stamp)
        val graph = T.graph(listOf(a))

        val dropped = DayReset.reset(store, graph, today, clock)
        DayReset.restore(store, graph, dropped)
        assertEquals(stamp, a.completion(today)!!.completedAt)
    }

    @Test
    fun `the dropped value survives a store round trip`() = runTest {
        // Guards the receipt itself: `Dropped` is a plain value, so a day reset and restored through
        // the store must still come back with the right number, not a defaulted 1.
        val store = InMemoryHabitsStore()
        val habit = T.habit(id = "timed")
        val row = T.done(habit, today, value = 1234.0)
        // The store needs the habit row too, not just the completion: `loadGraph` rebuilds habits
        // from the store, so without this it comes back empty and the assertion reads nothing.
        store.upsertHabit(habit)
        store.insertCompletion(row)
        val graph = T.graph(listOf(habit))

        val dropped = DayReset.reset(store, graph, today, clock)
        DayReset.restore(store, graph, dropped)

        val reloaded = store.loadGraph()
        assertEquals(1234.0, reloaded.habits.first().completion(today)!!.value, 0.0001)
    }
}
