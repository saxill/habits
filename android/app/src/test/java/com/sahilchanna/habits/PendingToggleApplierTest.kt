package com.sahilchanna.habits

import com.sahilchanna.habits.data.InMemoryHabitsStore
import com.sahilchanna.habits.data.MemoryStorage
import com.sahilchanna.habits.model.HabitType
import com.sahilchanna.habits.model.HabitsClock
import com.sahilchanna.habits.model.PendingToggleApplier
import com.sahilchanna.habits.model.PendingToggleQueue
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The widget/notification write path.
 *
 * Two things are being pinned here and they are different kinds of thing: the queue's *merge rules*
 * (what happens when a second tap arrives before the app has drained the first), and the applier's
 * *branches* (what each queued entry does to the store when it finally lands).
 */
class PendingToggleApplierTest {

    private val clock: HabitsClock = T.clock("2026-03-10T12:00:00Z")
    private val today = T.day("2026-03-10")
    private val key = "test.pending"

    private fun queue(storage: MemoryStorage) = PendingToggleQueue(storage, key)

    // MARK: - Merge rules

    @Test
    fun `a second tap replaces the first rather than queueing both`() {
        val q = queue(MemoryStorage())
        q.set("h", today, done = true, nowMillis = 1)
        q.set("h", today, done = false, nowMillis = 2)
        val entries = q.load()
        assertEquals(1, entries.size)
        assertFalse(entries.first().done)
    }

    @Test
    fun `glasses accumulate, because two taps are two glasses`() {
        val q = queue(MemoryStorage())
        q.logGlass("h", today, count = 1)
        q.logGlass("h", today, count = 1)
        q.logGlass("h", today, count = 2)
        assertEquals(4, q.load().first().glasses)
    }

    @Test
    fun `a pause does not erase a queued tick`() {
        val q = queue(MemoryStorage())
        q.set("h", today, done = true, nowMillis = 1)
        q.setPaused("h", paused = true, today = today, nowMillis = 2)
        val entry = q.load().first()
        assertTrue(entry.done)
        assertEquals(true, entry.pause)
    }

    @Test
    fun `a tick survives a glass and the glass survives the tick`() {
        val q = queue(MemoryStorage())
        q.logGlass("h", today, count = 1)
        q.set("h", today, done = true, nowMillis = 2)
        val entry = q.load().first()
        assertEquals(1, entry.glasses)
        assertTrue(entry.done)
    }

    @Test
    fun `discard supersedes everything queued for the day`() {
        val q = queue(MemoryStorage())
        q.set("h", today, done = true, nowMillis = 1)
        q.logGlass("h", today, count = 3)
        q.setPaused("h", paused = true, today = today, nowMillis = 2)
        q.stopTimer("h", today, nowMillis = 3)
        val entry = q.load().first()
        assertTrue(entry.stopTimer)
        assertFalse(entry.done)
        assertNull(entry.glasses)
        assertNull(entry.pause)
    }

    @Test
    fun `draining hands the entries over exactly once`() {
        val q = queue(MemoryStorage())
        q.set("h", today, done = true, nowMillis = 1)
        assertEquals(1, q.drain().size)
        assertTrue(q.drain().isEmpty())
    }

    @Test
    fun `different days are different entries`() {
        val q = queue(MemoryStorage())
        q.set("h", today, done = true, nowMillis = 1)
        q.set("h", today.minusDays(1), done = true, nowMillis = 2)
        assertEquals(2, q.load().size)
    }

    @Test
    fun `a corrupt queue reads as empty rather than crashing the app`() {
        val storage = MemoryStorage()
        storage.putString(key, "{not json")
        assertTrue(queue(storage).load().isEmpty())
    }

    // MARK: - Applier branches

    @Test
    fun `a queued tick becomes a completion`() = runTest {
        val store = InMemoryHabitsStore()
        val storage = MemoryStorage()
        val habit = T.habit(id = "h")
        val graph = T.graph(listOf(habit))

        queue(storage).set("h", today, done = true, nowMillis = clock.now().toEpochMilli())
        val changed = PendingToggleApplier(store, clock).apply(graph, queue(storage))

        assertTrue(changed)
        assertNotNull(habit.completion(today))
        assertEquals("widget", habit.completion(today)!!.source)
        assertEquals(1, store.completions().size)
    }

    @Test
    fun `a queued un-tick removes the completion`() = runTest {
        val store = InMemoryHabitsStore()
        val storage = MemoryStorage()
        val habit = T.habit(id = "h")
        T.done(habit, today)
        val graph = T.graph(listOf(habit))
        store.insertCompletion(habit.completions.first())

        queue(storage).set("h", today, done = false, nowMillis = clock.now().toEpochMilli())
        PendingToggleApplier(store, clock).apply(graph, queue(storage))

        assertNull(habit.completion(today))
        assertTrue(store.completions().isEmpty())
    }

    @Test
    fun `a tick for a past day is dropped, not credited`() = runTest {
        val store = InMemoryHabitsStore()
        val storage = MemoryStorage()
        val habit = T.habit(id = "h")
        val graph = T.graph(listOf(habit))

        // A reminder actioned after midnight for the previous day's nudge.
        queue(storage).set("h", today.minusDays(1), done = true, nowMillis = clock.now().toEpochMilli())
        PendingToggleApplier(store, clock).apply(graph, queue(storage))

        assertTrue(store.completions().isEmpty())
    }

    @Test
    fun `glasses increment a day that is already ticked off`() = runTest {
        val store = InMemoryHabitsStore()
        val storage = MemoryStorage()
        val water = T.habit(id = "w", icon = "drop")
        T.done(water, today, value = 1.0)
        val graph = T.graph(listOf(water))
        store.insertCompletion(water.completions.first())

        queue(storage).logGlass("w", today, count = 2)
        PendingToggleApplier(store, clock).apply(graph, queue(storage))

        // 1 + 2 — logging a glass is an increment, which is why it cannot go through `done`.
        assertEquals(3.0, water.completion(today)!!.value, 0.0001)
    }

    @Test
    fun `a first glass creates the day's completion`() = runTest {
        val store = InMemoryHabitsStore()
        val storage = MemoryStorage()
        val water = T.habit(id = "w", icon = "drop")
        val graph = T.graph(listOf(water))

        queue(storage).logGlass("w", today, count = 2)
        PendingToggleApplier(store, clock).apply(graph, queue(storage))

        assertEquals(2.0, water.completion(today)!!.value, 0.0001)
    }

    @Test
    fun `ticking a running timer records the elapsed seconds`() = runTest {
        val store = InMemoryHabitsStore()
        val storage = MemoryStorage()
        val timed = T.habit(id = "t", type = HabitType.TIMED, targetSeconds = 600)
        timed.startTimer(clock.now().minusSeconds(300))
        val graph = T.graph(listOf(timed))

        queue(storage).set("t", today, done = true, nowMillis = clock.now().toEpochMilli())
        PendingToggleApplier(store, clock).apply(graph, queue(storage))

        assertEquals(300.0, timed.completion(today)!!.value, 1.0)
        assertNull(timed.startedAt)
        assertNotNull(store.completions().firstOrNull())
    }

    @Test
    fun `discard stops the timer and logs nothing`() = runTest {
        val store = InMemoryHabitsStore()
        val storage = MemoryStorage()
        val timed = T.habit(id = "t", type = HabitType.TIMED)
        timed.startTimer(clock.now().minusSeconds(300))
        val graph = T.graph(listOf(timed))

        queue(storage).stopTimer("t", today, nowMillis = clock.now().toEpochMilli())
        val changed = PendingToggleApplier(store, clock).apply(graph, queue(storage))

        assertTrue(changed)
        assertNull(timed.startedAt)
        assertTrue(store.completions().isEmpty())
    }

    @Test
    fun `a pause is persisted even when the same entry carries a glass`() = runTest {
        val store = InMemoryHabitsStore()
        val storage = MemoryStorage()
        val water = T.habit(id = "w", icon = "drop")
        water.startTimer(clock.now().minusSeconds(60))
        val graph = T.graph(listOf(water))

        // The queue merges rather than replaces, so this is exactly what a timer-notification
        // pause followed by a widget glass produces: one entry, both fields set.
        val q = queue(storage)
        q.setPaused("w", paused = true, today = today, nowMillis = clock.now().toEpochMilli())
        q.logGlass("w", today, count = 1)
        PendingToggleApplier(store, clock).apply(graph, q)

        // The glass branch leaves the loop early, which is why the pause is persisted in its own
        // branch rather than at the end of the iteration.
        assertTrue(water.isPaused)
        assertEquals(1.0, water.completion(today)!!.value, 0.0001)
    }

    @Test
    fun `an entry for a habit that no longer exists is ignored`() = runTest {
        val store = InMemoryHabitsStore()
        val storage = MemoryStorage()
        val graph = T.graph(emptyList())

        queue(storage).set("gone", today, done = true, nowMillis = clock.now().toEpochMilli())
        val changed = PendingToggleApplier(store, clock).apply(graph, queue(storage))

        assertFalse(changed)
        assertTrue(store.completions().isEmpty())
    }

    @Test
    fun `an empty queue changes nothing`() = runTest {
        val store = InMemoryHabitsStore()
        val graph = T.graph(listOf(T.habit(id = "h")))
        assertFalse(PendingToggleApplier(store, clock).apply(graph, queue(MemoryStorage())))
    }
}
