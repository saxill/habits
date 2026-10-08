package com.sahilchanna.habits

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The clock, which is where the port's one genuinely new feature lives: a configurable day-reset
 * hour. Every one of these is a wall-clock question answered deterministically, which is only
 * possible because the clock is injected.
 */
class HabitsClockTest {

    @Test
    fun `the default reset hour is midnight, matching the iOS build`() {
        val clock = T.clock("2026-03-10T23:59:00Z")
        assertEquals(T.day("2026-03-10"), clock.today())
        assertEquals(T.day("2026-03-11"), T.clock("2026-03-11T00:00:00Z").today())
    }

    @Test
    fun `a later reset hour keeps a small-hours session on the day it started`() {
        val clock = T.clock("2026-03-11T01:30:00Z", resetHour = 4)
        // 01:30 is still "yesterday" to a night owl, which is the whole point of the setting.
        assertEquals(T.day("2026-03-10"), clock.today())
        // 03:59 still belongs to the 10th; 04:00 starts the 11th.
        assertEquals(T.day("2026-03-10"), T.clock("2026-03-11T03:59:00Z", resetHour = 4).today())
        assertEquals(T.day("2026-03-11"), T.clock("2026-03-11T04:00:00Z", resetHour = 4).today())
    }

    @Test
    fun `the reset hour is read on every call, so a preference change takes effect at once`() {
        var hour = 0
        val fixed = java.time.Clock.fixed(java.time.Instant.parse("2026-03-11T02:00:00Z"), T.UTC)
        val clock = com.sahilchanna.habits.model.HabitsClock(fixed) { hour }
        assertEquals(T.day("2026-03-11"), clock.today())
        hour = 4
        // No reconstruction needed — a settings screen flip is live.
        assertEquals(T.day("2026-03-10"), clock.today())
    }

    @Test
    fun `an out-of-range reset hour is clamped rather than trusted`() {
        val fixed = java.time.Clock.fixed(java.time.Instant.parse("2026-03-11T02:00:00Z"), T.UTC)
        // A hand-edited preference must not throw on every render.
        assertEquals(T.day("2026-03-10"), com.sahilchanna.habits.model.HabitsClock(fixed) { 99 }.today())
        assertEquals(T.day("2026-03-11"), com.sahilchanna.habits.model.HabitsClock(fixed) { -5 }.today())
    }

    @Test
    fun `weekday index runs one for Sunday through seven for Saturday`() {
        val clock = T.clock("2026-03-10T12:00:00Z")
        assertEquals(1, clock.weekdayIndex(T.day("2026-03-08")))
        assertEquals(7, clock.weekdayIndex(T.day("2026-03-14")))
    }

    @Test
    fun `a week runs Monday to Sunday`() {
        val clock = T.clock("2026-03-10T12:00:00Z")
        val week = clock.weekDates(T.day("2026-03-10"))
        assertEquals(7, week.size)
        assertEquals(T.day("2026-03-09"), week.first())
        assertEquals(T.day("2026-03-15"), week.last())
        assertEquals(java.time.DayOfWeek.MONDAY, week.first().dayOfWeek)
    }

    @Test
    fun `a completion at the reset boundary lands on the right side of it`() {
        val clock = T.clock("2026-03-11T02:00:00Z", resetHour = 4)
        // The instant a completion is stamped with is converted in exactly one place, so this is
        // the test that matters for every streak, stat and achievement downstream.
        assertEquals(T.day("2026-03-10"), clock.dayOf(java.time.Instant.parse("2026-03-11T02:00:00Z")))
        assertEquals(T.day("2026-03-11"), clock.dayOf(java.time.Instant.parse("2026-03-11T05:00:00Z")))
    }

    @Test
    fun `a reminder time round trips through the clock`() {
        val clock = T.clock("2026-03-10T12:00:00Z")
        val fire = clock.instantAt(T.day("2026-03-11"), 8 * 60 + 30)
        assertEquals(T.day("2026-03-11"), clock.dayOf(fire))
        assertEquals(8 * 60 + 30, clock.minutesFromMidnight(fire))
        assertEquals("08:30", clock.formatClock(8 * 60 + 30))
    }

    @Test
    fun `is today is the reset-aware question, not a date comparison`() {
        val clock = T.clock("2026-03-11T01:00:00Z", resetHour = 4)
        assertTrue(clock.isToday(T.day("2026-03-10")))
        assertFalse(clock.isToday(T.day("2026-03-11")))
    }
}
