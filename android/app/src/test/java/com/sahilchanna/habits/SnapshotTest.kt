package com.sahilchanna.habits

import com.sahilchanna.habits.data.HabitsShared
import com.sahilchanna.habits.data.MemoryStorage
import com.sahilchanna.habits.data.Settings
import com.sahilchanna.habits.model.CompletionDayAnchor
import com.sahilchanna.habits.model.SnapshotBuilder
import com.sahilchanna.habits.model.Snapshots
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

/** The widget snapshot: what it carries, and the two in-place edits that make a widget tap feel
 * immediate rather than waiting for the app to come forward. */
class SnapshotTest {

    private val clock = T.clock("2026-03-10T12:00:00Z")
    private val today = T.day("2026-03-10")

    private val colors = SnapshotBuilder.Colors("#0A0A0D", "#E8E8E8", "#6E6E73", "#FFB454")

    @Test
    fun `a snapshot round trips through storage`() {
        val storage = MemoryStorage()
        val snap = Snapshots.placeholder(clock)
        Snapshots.save(storage, snap)
        val loaded = Snapshots.load(storage)
        assertNotNull(loaded)
        assertEquals(snap.totalCount, loaded!!.totalCount)
        assertEquals(snap.routines.first().habits.size, loaded.routines.first().habits.size)
        assertEquals(snap.day, loaded.day)
    }

    @Test
    fun `a missing or corrupt snapshot reads as null`() {
        val storage = MemoryStorage()
        assertNull(Snapshots.load(storage))
        storage.putString(HabitsShared.SNAPSHOT_KEY, "not json at all")
        assertNull(Snapshots.load(storage))
    }

    @Test
    fun `a toggle flips the habit and moves the counter by one`() {
        val storage = MemoryStorage()
        Snapshots.save(storage, Snapshots.placeholder(clock))
        // "read" starts not done.
        Snapshots.applyToggle(storage, "p3", done = true, now = clock.now())
        val loaded = Snapshots.load(storage)!!
        assertTrue(loaded.flatHabits.first { it.id == "p3" }.done)
        assertEquals(3, loaded.doneCount)
    }

    @Test
    fun `a repeated toggle is idempotent, not a second increment`() {
        val storage = MemoryStorage()
        Snapshots.save(storage, Snapshots.placeholder(clock))
        Snapshots.applyToggle(storage, "p3", done = true, now = clock.now())
        Snapshots.applyToggle(storage, "p3", done = true, now = clock.now())
        assertEquals(3, Snapshots.load(storage)!!.doneCount)
    }

    @Test
    fun `the counter cannot drift out of range`() {
        val storage = MemoryStorage()
        Snapshots.save(storage, Snapshots.placeholder(clock))
        // Un-ticking the two that are done, then un-ticking them again.
        Snapshots.applyToggle(storage, "p1", done = false, now = clock.now())
        Snapshots.applyToggle(storage, "p2", done = false, now = clock.now())
        Snapshots.applyToggle(storage, "p1", done = false, now = clock.now())
        assertEquals(0, Snapshots.load(storage)!!.doneCount)
    }

    @Test
    fun `a toggle for an unknown habit changes nothing`() {
        val storage = MemoryStorage()
        Snapshots.save(storage, Snapshots.placeholder(clock))
        Snapshots.applyToggle(storage, "nope", done = true, now = clock.now())
        assertEquals(2, Snapshots.load(storage)!!.doneCount)
    }

    @Test
    fun `clearing the running line keeps everything else`() {
        val storage = MemoryStorage()
        val base = Snapshots.placeholder(clock)
        Snapshots.save(
            storage,
            base.copy(running = com.sahilchanna.habits.model.HabitsSnapshot.Running("stretch", 0, 600.0, "#00D7C3")),
        )
        Snapshots.clearRunning(storage, clock.now())
        val loaded = Snapshots.load(storage)!!
        assertNull(loaded.running)
        assertEquals(base.totalCount, loaded.totalCount)
    }

    @Test
    fun `clearing a snapshot that has no running timer leaves it alone`() {
        val storage = MemoryStorage()
        Snapshots.save(storage, Snapshots.placeholder(clock))
        val before = storage.getString(HabitsShared.SNAPSHOT_KEY)
        Snapshots.clearRunning(storage, clock.now())
        assertEquals(before, storage.getString(HabitsShared.SNAPSHOT_KEY))
    }

    // MARK: - Builder

    @Test
    fun `the builder counts only habits scheduled today`() {
        // A Monday-only habit is not part of a Tuesday's total, or the widget would show a
        // permanently unticked row on six days out of seven.
        val mondayOnly = T.habit(id = "m", scheduleDays = setOf(2))
        val everyDay = T.habit(id = "e", name = "read")
        T.done(everyDay, today)
        val graph = T.graph(listOf(mondayOnly, everyDay))

        val snap = SnapshotBuilder.build(graph, clock, colors)
        val habits = snap.flatHabits
        assertEquals(1, habits.size)
        assertEquals("e", habits.first().id)
        assertEquals(1, snap.doneCount)
        assertEquals(1, snap.totalCount)
    }

    @Test
    fun `the builder files routine-less habits under unfiled`() {
        val filed = T.habit(id = "f", routine = T.routine(id = "r"))
        val loose = T.habit(id = "l", name = "journal")
        val graph = T.graph(listOf(filed, loose), routines = listOf(filed.routine!!))

        val snap = SnapshotBuilder.build(graph, clock, colors)
        // Without this pass an unfiled habit vanishes from every widget while still counting
        // in stats and reminders.
        val unfiled = snap.routines.first { it.id == Snapshots.UNFILED_ROUTINE_ID }
        assertEquals(listOf("l"), unfiled.habits.map { it.id })
    }

    @Test
    fun `the builder carries the streak and the theme`() {
        val habit = T.habit(id = "h")
        T.done(habit, today)
        T.done(habit, today.minusDays(1))
        val graph = T.graph(listOf(habit))

        val snap = SnapshotBuilder.build(graph, clock, colors)
        assertEquals(2, snap.flatHabits.first().streak)
        assertEquals(2, snap.streak)
        assertEquals("#0A0A0D", snap.background)
        assertEquals("#FFB454", snap.accent)
    }

    @Test
    fun `the running line is the most recently started timer`() {
        val older = T.habit(id = "a", name = "stretch")
        val newer = T.habit(id = "b", name = "focus block")
        older.startTimer(clock.now().minusSeconds(600))
        newer.startTimer(clock.now().minusSeconds(60))
        val graph = T.graph(listOf(older, newer))

        val snap = SnapshotBuilder.build(graph, clock, colors)
        assertEquals("focus block", snap.running?.name)
    }

    @Test
    fun `no running timer is a null line`() {
        val graph = T.graph(listOf(T.habit(id = "h")))
        assertNull(SnapshotBuilder.build(graph, clock, colors).running)
    }

    // MARK: - Day anchoring

    @Test
    fun `a legacy midnight day is folded into a calendar day once`() = runTest {
        val store = com.sahilchanna.habits.data.InMemoryHabitsStore()
        val settings = Settings(MemoryStorage())
        val habit = T.habit(id = "h")
        val row = T.done(habit, today)
        // A row written by the old build: a local-midnight instant in the same field.
        row.legacyDayMillis = Instant.parse("2026-03-10T00:00:00Z").toEpochMilli()
        store.upsertHabit(habit)
        store.insertCompletion(row)

        assertEquals(1, CompletionDayAnchor.migrateIfNeeded(store, settings, clock))
        val migrated = store.completions().first()
        assertEquals(today, migrated.day)
        assertNull(migrated.legacyDayMillis)
        // And it does not run again.
        assertEquals(0, CompletionDayAnchor.migrateIfNeeded(store, settings, clock))
    }
}
