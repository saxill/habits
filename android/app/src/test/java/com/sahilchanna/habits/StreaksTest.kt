package com.sahilchanna.habits

import com.sahilchanna.habits.model.HabitsClock
import com.sahilchanna.habits.model.Streaks
import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.Clock
import java.time.Instant
import java.time.ZoneId

/** Streak math, pinned to fixed dates — the today-grace and the schedule-since-creation bound are
 * the two behaviours worth locking down, and neither can be checked against a live clock. */
class StreaksTest {

    private val clock: HabitsClock = T.clock("2026-03-10T12:00:00Z")
    private val today = T.day("2026-03-10")

    @Test
    fun `streak counts today and the days before it`() {
        val habit = T.habit()
        T.done(habit, today)
        T.done(habit, today.minusDays(1))
        T.done(habit, today.minusDays(2))
        assertEquals(3, Streaks.habitStreak(habit, today))
    }

    @Test
    fun `a day not yet done does not break the streak`() {
        val habit = T.habit()
        // Everything through yesterday; today is still untouched, which must not read as zero.
        T.done(habit, today.minusDays(1))
        T.done(habit, today.minusDays(2))
        assertEquals(2, Streaks.habitStreak(habit, today))
    }

    @Test
    fun `a missed day ends the streak`() {
        val habit = T.habit()
        T.done(habit, today)
        T.done(habit, today.minusDays(1))
        // Skipped yesterday-minus-two on purpose.
        T.done(habit, today.minusDays(3))
        assertEquals(2, Streaks.habitStreak(habit, today))
    }

    @Test
    fun `no history is no streak`() {
        assertEquals(0, Streaks.habitStreak(T.habit(), today))
    }

    @Test
    fun `best streak survives the current one ending`() {
        val habit = T.habit()
        // A 4-day run a fortnight ago, then nothing.
        for (offset in 20L..23L) T.done(habit, today.minusDays(offset))
        assertEquals(4, Streaks.bestStreak(habit))
        assertEquals(0, Streaks.habitStreak(habit, today))
    }

    @Test
    fun `overall streak needs only one completion a day`() {
        val a = T.habit(id = "a")
        val b = T.habit(id = "b")
        T.done(a, today)
        T.done(b, today.minusDays(1))
        T.done(a, today.minusDays(2))
        assertEquals(3, Streaks.overall(listOf(a, b).flatMap { it.completions }, today))
    }

    @Test
    fun `best overall is the longest run ever, not the one standing now`() {
        val a = T.habit(id = "a")
        for (offset in 0L..2L) T.done(a, today.minusDays(offset))
        for (offset in 30L..35L) T.done(a, today.minusDays(offset))
        assertEquals(3, Streaks.overall(a.completions, today))
        assertEquals(6, Streaks.bestOverall(a.completions))
    }

    @Test
    fun `day ratio is minus one when nothing was scheduled`() {
        // A habit scheduled only on Mondays, asked about a Tuesday that is past its creation.
        val mondayOnly = T.habit(scheduleDays = setOf(2), createdAt = Instant.parse("2026-01-01T00:00:00Z"))
        // 2026-03-10 is a Tuesday.
        assertEquals(-1.0, Streaks.dayRatio(today, listOf(mondayOnly), clock), 0.0001)
    }

    @Test
    fun `day ratio ignores days before a habit was created`() {
        val habit = T.habit(createdAt = Instant.parse("2026-03-10T00:00:00Z"))
        T.done(habit, today)
        // Today's ratio is 1. A day last week is not "missed" — the habit did not exist.
        assertEquals(1.0, Streaks.dayRatio(today, listOf(habit), clock), 0.0001)
        assertEquals(-1.0, Streaks.dayRatio(today.minusDays(7), listOf(habit), clock), 0.0001)
    }

    @Test
    fun `day ratio is the done fraction of what was due`() {
        val a = T.habit(id = "a")
        val b = T.habit(id = "b")
        T.done(a, today)
        assertEquals(0.5, Streaks.dayRatio(today, listOf(a, b), clock), 0.0001)
    }

    @Test
    fun `weekday index is one for Sunday through seven for Saturday`() {
        // 2026-03-08 is a Sunday.
        assertEquals(1, Streaks.weekdayIndex(T.day("2026-03-08")))
        assertEquals(2, Streaks.weekdayIndex(T.day("2026-03-09")))
        assertEquals(7, Streaks.weekdayIndex(T.day("2026-03-14")))
    }

    @Test
    fun `streak walk is unaffected by a zone offset`() {
        // The iOS build had to normalise each step because a midnight can be missing; here the walk
        // is plain calendar arithmetic, so a zone with a DST jump must give the same answer.
        val chile = HabitsClock(
            Clock.fixed(Instant.parse("2026-09-06T12:00:00Z"), ZoneId.of("America/Santiago")),
        ) { 0 }
        val localToday = chile.today()
        val habit = T.habit()
        T.done(habit, localToday)
        T.done(habit, localToday.minusDays(1))
        assertEquals(2, Streaks.habitStreak(habit, localToday))
    }
}
