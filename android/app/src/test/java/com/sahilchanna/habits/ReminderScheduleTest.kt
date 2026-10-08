package com.sahilchanna.habits

import com.sahilchanna.habits.model.HabitType
import com.sahilchanna.habits.model.Reminders
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The reminder arithmetic.
 *
 * These decisions are the ones that used to be wrong: a reminder for a habit already ticked off,
 * a reminder whose time has passed, and the shared budget between the habit and water schedules.
 */
class ReminderScheduleTest {

    private val clock = T.clock("2026-03-10T12:00:00Z")
    private val now = clock.now()

    @Test
    fun `occurrences cover the lookahead window, soonest first`() {
        val habit = T.habit(reminderMinutesFromMidnight = 8 * 60)
        val out = Reminders.habitOccurrences(listOf(habit), emptyMap(), now, clock)
        // Today's 08:00 is behind us, so the window starts tomorrow: the 11th through the 16th.
        assertEquals(6, out.size)
        assertEquals(T.day("2026-03-11"), out.first().day)
        assertEquals(T.day("2026-03-16"), out.last().day)
        assertTrue(out.zipWithNext().all { (a, b) -> a.fire <= b.fire })
    }

    @Test
    fun `a reminder later today is still scheduled`() {
        val habit = T.habit(reminderMinutesFromMidnight = 20 * 60)
        val out = Reminders.habitOccurrences(listOf(habit), emptyMap(), now, clock)
        assertEquals(T.day("2026-03-10"), out.first().day)
        assertEquals(7, out.size)
    }

    @Test
    fun `a habit with no reminder time is skipped`() {
        val habit = T.habit(reminderMinutesFromMidnight = null)
        assertTrue(Reminders.habitOccurrences(listOf(habit), emptyMap(), now, clock).isEmpty())
    }

    @Test
    fun `only the habit's scheduled weekdays appear`() {
        // Monday only. 2026-03-16 is the next Monday inside the window.
        val mondayOnly = T.habit(scheduleDays = setOf(2), reminderMinutesFromMidnight = 9 * 60)
        val out = Reminders.habitOccurrences(listOf(mondayOnly), emptyMap(), now, clock)
        assertEquals(1, out.size)
        assertEquals(T.day("2026-03-16"), out.first().day)
    }

    @Test
    fun `a day already ticked off is not reminded`() {
        val habit = T.habit(id = "h", reminderMinutesFromMidnight = 8 * 60)
        val done = mapOf("h" to setOf(T.day("2026-03-11")))
        val out = Reminders.habitOccurrences(listOf(habit), done, now, clock)
        // Six days in the window (today's 08:00 has passed), one of them ticked off.
        assertEquals(5, out.size)
        assertFalse(out.any { it.day == T.day("2026-03-11") })
    }

    @Test
    fun `alarm ids are allocated from a base that leaves room for the water schedule`() {
        assertEquals(Reminders.habitAlarmId(0), Reminders.habitAlarmId(0))
        assertTrue(Reminders.habitAlarmId(5) > Reminders.habitAlarmId(4))
        assertTrue(Reminders.habitAlarmId(0) >= 1000)
    }

    // MARK: - Water

    @Test
    fun `water slots include the end hour`() {
        val slots = Reminders.waterSlots(startHour = 9, endHour = 21, intervalMinutes = 120)
        assertEquals(listOf(9 * 60, 11 * 60, 13 * 60, 15 * 60, 17 * 60, 19 * 60, 21 * 60), slots)
    }

    @Test
    fun `water slots honour a half-hour interval`() {
        assertEquals(25, Reminders.waterSlots(8, 20, 30).size)
    }

    @Test
    fun `an inverted window is no window`() {
        assertTrue(Reminders.waterSlots(21, 9, 60).isEmpty())
        // Equal hours would be one reminder at a single instant, not a window.
        assertTrue(Reminders.waterSlots(9, 9, 60).isEmpty())
    }

    @Test
    fun `an interval under a quarter hour is refused`() {
        assertTrue(Reminders.waterSlots(9, 21, 10).isEmpty())
        assertTrue(Reminders.waterSlots(9, 21, 15).isNotEmpty())
    }

    @Test
    fun `water occurrences skip what is already behind us`() {
        val out = Reminders.waterOccurrences(
            habit = null,
            startHour = 9,
            endHour = 21,
            intervalMinutes = 120,
            now = now,
            clock = clock,
        )
        // Five slots left today (13:00 onward) plus a full seven tomorrow.
        assertEquals(12, out.size)
        assertEquals(13 * 60, out.first().minutes)
        assertEquals(T.day("2026-03-10"), out.first().day)
        assertEquals(T.day("2026-03-11"), out.last().day)
    }

    @Test
    fun `a water habit is a check-off with a drop or a matching name`() {
        assertTrue(Reminders.isWaterHabit(T.habit(icon = "drop")))
        assertTrue(Reminders.isWaterHabit(T.habit(name = "drink water")))
        assertTrue(Reminders.isWaterHabit(T.habit(name = "hydrate")))
        assertFalse(Reminders.isWaterHabit(T.habit(name = "read")))
    }

    @Test
    fun `a timed habit is never the water habit`() {
        // A timed habit keeps seconds in the same field the glass tally uses, so a timed habit
        // named "water" would report 1,800 glasses.
        assertFalse(Reminders.isWaterHabit(T.habit(name = "water", type = HabitType.TIMED)))
        assertFalse(Reminders.isWaterHabit(T.habit(icon = "drop", type = HabitType.TIMED)))
    }

    @Test
    fun `the drop icon wins over an earlier name match`() {
        val named = T.habit(id = "named", name = "drink water")
        val dropped = T.habit(id = "dropped", icon = "drop")
        assertEquals("dropped", Reminders.waterHabit(listOf(named, dropped))?.id)
    }

    @Test
    fun `no water habit is a null, not a guess`() {
        assertNull(Reminders.waterHabit(listOf(T.habit(name = "read"), T.habit(name = "journal"))))
    }

    @Test
    fun `glasses read the day's completion value`() {
        val water = T.habit(id = "water", icon = "drop")
        assertEquals(0, Reminders.glasses(water, T.day("2026-03-10")))
        T.done(water, T.day("2026-03-10"), value = 5.0)
        assertEquals(5, Reminders.glasses(water, T.day("2026-03-10")))
        assertEquals(0, Reminders.glasses(null, T.day("2026-03-10")))
    }

    @Test
    fun `a slot reads as a clock time`() {
        assertEquals("08:30", Reminders.slotLabel(8 * 60 + 30))
        assertEquals("00:00", Reminders.slotLabel(0))
    }
}
