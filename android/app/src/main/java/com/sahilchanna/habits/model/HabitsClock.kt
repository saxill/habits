package com.sahilchanna.habits.model

import java.time.Clock
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneId
import java.time.temporal.ChronoUnit

/**
 * Every date and time decision in the app comes through here, so a test can pin "now" and a
 * machine in a different zone cannot change an answer.
 *
 * Two things this fixes that the iOS build had to work around:
 *
 *  - Days are `LocalDate`, not instants. SwiftData stores a completion's day as *noon* of that
 *    day because a stored midnight moves when the device's zone moves (`Date.dayAnchor`), and
 *    the streak walk re-normalises every step because a `date(byAdding:)` from a midnight that
 *    does not exist (Chile, Egypt, Cuba move the clock at 24:00) drifts off the grid of
 *    day-starts (`Streaks.step`). A calendar date has neither problem, so the walk here is plain
 *    `plusDays` and none of that arithmetic is needed.
 *  - The day a completion belongs to is decided once, here, from a configurable reset hour
 *    rather than from a fixed midnight. Zero is the default and matches the iOS behaviour
 *    exactly; a night-owl who logs at 01:00 can set it to 4 so that session still counts as the
 *    previous day.
 */
class HabitsClock(
    val clock: Clock = Clock.systemDefaultZone(),
    /** Hour the new day starts at, 0…23. Read lazily so a preference change takes effect at once. */
    private val dayResetHour: () -> Int = { 0 },
) {
    val zone: ZoneId get() = clock.zone

    fun now(): Instant = clock.instant()

    private fun resetHour(): Int = dayResetHour().coerceIn(0, 23)

    /** The completion-day an instant falls on, honouring the reset hour. */
    fun dayOf(instant: Instant): LocalDate {
        val shifted = instant.minus(Duration.ofHours(resetHour().toLong()))
        return shifted.atZone(zone).toLocalDate()
    }

    fun today(): LocalDate = dayOf(now())

    /** The instant a day begins — its reset hour on that calendar date. */
    fun startOfDay(day: LocalDate): Instant =
        day.atTime(resetHour(), 0).atZone(zone).toInstant()

    /**
     * Noon of the day. Not used for storage (that is the epoch day) but it is the form the
     * widget snapshot and the live-timer payload carry when a bare instant is needed, which is
     * the one shape that survives a zone change.
     */
    fun dayAnchor(day: LocalDate): Instant = day.atTime(12, 0).atZone(zone).toInstant()

    fun isToday(day: LocalDate): Boolean = day == today()

    /** Calendar weekday as 1…7 (Sun…Sat), matching the schedule field the model stores. */
    fun weekdayIndex(day: LocalDate): Int = day.dayOfWeek.value % 7 + 1

    /** Monday-start week containing `day`, matching `Date.weekDates`. */
    fun weekDates(day: LocalDate): List<LocalDate> {
        val monday = mondayOf(day)
        return (0L until 7L).map { monday.plusDays(it) }
    }

    fun mondayOf(day: LocalDate): LocalDate = day.minusDays((day.dayOfWeek.value - 1).toLong())

    fun daysBetween(from: LocalDate, to: LocalDate): Long = ChronoUnit.DAYS.between(from, to)

    /** Minutes from midnight, the unit a habit's reminder is stored in. */
    fun localTime(minutesFromMidnight: Int): LocalTime =
        LocalTime.of((minutesFromMidnight / 60) % 24, minutesFromMidnight % 60)

    fun instantAt(day: LocalDate, minutesFromMidnight: Int): Instant {
        val t = localTime(minutesFromMidnight)
        return LocalDateTime.of(day, t).atZone(zone).toInstant()
    }

    fun minutesFromMidnight(instant: Instant): Int {
        val t = instant.atZone(zone).toLocalTime()
        return t.hour * 60 + t.minute
    }

    fun hourOf(instant: Instant): Int = instant.atZone(zone).hour

    /** `08:00` — how a reminder time is reported on a habit row. */
    fun formatClock(minutesFromMidnight: Int): String =
        "%02d:%02d".format((minutesFromMidnight / 60) % 24, minutesFromMidnight % 60)
}
