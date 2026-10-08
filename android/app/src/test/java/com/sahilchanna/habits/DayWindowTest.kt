package com.sahilchanna.habits

import com.sahilchanna.habits.model.DayWindow
import com.sahilchanna.habits.model.HabitDays
import com.sahilchanna.habits.model.HabitsClock
import com.sahilchanna.habits.model.StatsRange
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.DayOfWeek
import java.time.Instant

/** The stats windows: whole weeks, the display cap, and the completion rate's denominator. */
class DayWindowTest {

    private val clock: HabitsClock = T.clock("2026-03-10T12:00:00Z")
    private val today = T.day("2026-03-10")

    @Test
    fun `the habit dive goes down to a week and out to all of history`() {
        assertEquals(
            listOf(StatsRange.D7, StatsRange.D30, StatsRange.D90, StatsRange.D365, StatsRange.ALL),
            StatsRange.habit,
        )
        // The overview is a density view, so it starts at 30d and stops where it stays legible.
        assertEquals(listOf(StatsRange.D30, StatsRange.D90, StatsRange.D180), StatsRange.overview)
    }

    @Test
    fun `an unknown range falls back rather than crashing a saved preference`() {
        assertEquals(StatsRange.D90, StatsRange.fromRaw("nonsense"))
        assertEquals(StatsRange.D7, StatsRange.fromRaw("7d"))
    }

    @Test
    fun `a window starts on a Monday and ends today`() {
        val window = DayWindow.display(StatsRange.D7, emptyList(), today, clock)
        assertEquals(DayOfWeek.MONDAY, window.from.dayOfWeek)
        assertEquals(today, window.to)
        assertTrue(window.from <= window.start)
    }

    @Test
    fun `the display cap bounds a long range but the numbers do not`() {
        val habit = T.habit(createdAt = Instant.parse("2020-01-01T00:00:00Z"))
        val window = DayWindow.display(StatsRange.ALL, listOf(habit), today, clock)
        // The grid starts at the cap, not at the habit's real beginning…
        assertEquals(today.minusDays(DayWindow.MAX_WEEKS * 7L - 1), window.start)
        assertTrue(window.start > DayWindow.rangeStart(StatsRange.ALL, listOf(habit), today, clock))
        // …and the columns are whole weeks, so a partial current week adds one past the cap.
        assertTrue(window.weeks <= DayWindow.MAX_WEEKS + 1)
        // The label says which span it is showing, rather than calling six months "all".
        assertEquals("last ${window.weeks} weeks", window.label(StatsRange.ALL))
    }

    @Test
    fun `a short range is labelled by the range itself`() {
        val window = DayWindow.display(StatsRange.D7, emptyList(), today, clock)
        assertEquals("last 7d", window.label(StatsRange.D7))
    }

    @Test
    fun `all history with no habits is just today`() {
        assertEquals(
            DayWindow.rangeStart(StatsRange.ALL, emptyList(), today, clock),
            today,
        )
    }

    @Test
    fun `the grid keeps its shape and nulls what is out of range`() {
        // A window whose first Monday precedes the range's own start.
        val from = T.day("2026-03-02")
        val start = T.day("2026-03-05")
        val grid = DayWindow.grid(from, today, start)
        assertEquals(2, grid.size)
        assertEquals(7, grid.first().size)
        assertNull(grid.first()[0])
        assertEquals(start, grid.first()[3])
        // Nothing after today is invented either.
        assertNull(grid.last()[5])
        assertEquals(today, grid.last()[1])
    }

    @Test
    fun `the flat day list drops the padding`() {
        val days = DayWindow.days(T.day("2026-03-02"), today, T.day("2026-03-05"))
        assertEquals(6, days.size)
        assertEquals(T.day("2026-03-05"), days.first())
        assertEquals(today, days.last())
    }

    @Test
    fun `a contiguous list is inclusive and ordered`() {
        val days = DayWindow.contiguous(T.day("2026-03-08"), today)
        assertEquals(listOf(T.day("2026-03-08"), T.day("2026-03-09"), today), days)
        assertTrue(DayWindow.contiguous(today, T.day("2026-03-08")).isEmpty())
    }

    @Test
    fun `a rate counts only days a habit was due`() {
        val habit = T.habit(createdAt = Instant.parse("2026-03-08T00:00:00Z"))
        T.done(habit, T.day("2026-03-09"))
        // 03-08 and 03-09 were due and only one was done; 03-10 is due and not done.
        val days = DayWindow.contiguous(T.day("2026-03-08"), today)
        val tally = HabitDays.tally(listOf(habit), days, clock)
        assertEquals(3, tally.due)
        assertEquals(1, tally.done)
        assertEquals(1.0 / 3.0, tally.rate, 0.0001)
    }

    @Test
    fun `days before a habit existed are not due`() {
        val habit = T.habit(createdAt = Instant.parse("2026-03-10T00:00:00Z"))
        T.done(habit, today)
        val days = DayWindow.contiguous(T.day("2026-03-01"), today)
        val tally = HabitDays.tally(listOf(habit), days, clock)
        // Ten calendar days, but only one the habit could have been done on.
        assertEquals(1, tally.due)
        assertEquals(1, tally.done)
        assertEquals(1.0, tally.rate, 0.0001)
    }

    @Test
    fun `days a habit was not scheduled are not due`() {
        val mondayOnly = T.habit(
            createdAt = Instant.parse("2026-03-01T00:00:00Z"),
            scheduleDays = setOf(2),
        )
        T.done(mondayOnly, T.day("2026-03-09"))
        val days = DayWindow.contiguous(T.day("2026-03-02"), today)
        val tally = HabitDays.tally(listOf(mondayOnly), days, clock)
        // Two Mondays in the window (03-02 and 03-09), one done.
        assertEquals(2, tally.due)
        assertEquals(1, tally.done)
    }

    @Test
    fun `a tally with nothing due is zero, not a division by zero`() {
        assertEquals(0.0, HabitDays.rate(HabitDays.Tally(0, 0)), 0.0001)
    }
}
