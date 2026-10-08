package com.sahilchanna.habits.model

import com.sahilchanna.habits.data.Habit
import java.time.LocalDate

/**
 * The windows the stats screen offers. Ranges are expressed in whole weeks so the heatmap's
 * columns are weeks and its rows are weekdays — a "last N days" grid whose columns are *not*
 * weekdays reads as a calendar while quietly not being one.
 */
enum class StatsRange(val raw: String, val days: Int?) {
    D7("7d", 7),
    D30("30d", 30),
    D90("90d", 90),
    D180("180d", 180),
    D365("365d", 365),
    ALL("all", null);

    companion object {
        /** The overview is a density view, so it starts at 30d and stops where it stays legible. */
        val overview: List<StatsRange> = listOf(D30, D90, D180)

        /** The per-habit dive goes down to a week and out to all of history. */
        val habit: List<StatsRange> = listOf(D7, D30, D90, D365, ALL)

        fun fromRaw(raw: String): StatsRange = entries.firstOrNull { it.raw == raw } ?: D90
    }
}

/**
 * The whole weeks a range touches: Monday-start, ending with the week containing today.
 */
object DayWindow {
    /**
     * A heatmap of one week per column stops being legible well before a year: 53 columns on a
     * phone is a 3dp smudge and the weekday labels collide. So the *visual* is capped at about
     * half a year and says which span it is showing, while the numbers beside it still cover the
     * full range the user selected.
     */
    const val MAX_WEEKS = 27

    data class Window(
        /** Monday of the first displayed week. */
        val from: LocalDate,
        /** today */
        val to: LocalDate,
        /** First day inside the range — `from` unless the cap bit. */
        val start: LocalDate,
        /** Columns actually drawn. */
        val weeks: Int,
    ) {
        /** `last 90d`, or `last 27 weeks` when the cap shortened the visual. */
        fun label(range: StatsRange): String {
            val rangeWeeks = range.days?.let { it / 7 + 1 } ?: Int.MAX_VALUE
            return if (weeks < rangeWeeks) "last $weeks weeks" else "last ${range.raw}"
        }
    }

    /** First day the range covers, before any display cap. */
    fun rangeStart(range: StatsRange, habits: List<Habit>, today: LocalDate, clock: HabitsClock): LocalDate {
        val days = range.days
            ?: return habits.minOfOrNull { Achievements.firstTrackedDay(it, clock) } ?: today
        return today.minusDays((days - 1).toLong())
    }

    fun display(range: StatsRange, habits: List<Habit>, today: LocalDate, clock: HabitsClock): Window {
        val raw = rangeStart(range, habits, today, clock)
        val capped = today.minusDays((MAX_WEEKS * 7 - 1).toLong())
        val start = maxOf(raw, capped)
        val from = clock.mondayOf(start)
        val weeks = (clock.daysBetween(from, today) / 7).toInt() + 1
        return Window(from, today, start, weeks)
    }

    /**
     * Every date in the grid, column by column, Monday first. Dates before `start` or after `to`
     * are null so the grid keeps its shape without inventing data.
     */
    fun grid(from: LocalDate, to: LocalDate, start: LocalDate): List<List<LocalDate?>> {
        val columns = mutableListOf<List<LocalDate?>>()
        var weekStart = from
        while (!weekStart.isAfter(to)) {
            columns.add((0L until 7L).map { offset ->
                val day = weekStart.plusDays(offset)
                if (day >= start && !day.isAfter(to)) day else null
            })
            weekStart = weekStart.plusDays(7)
        }
        return columns
    }

    /** The grid's in-range days as a flat list. */
    fun days(from: LocalDate, to: LocalDate, start: LocalDate): List<LocalDate> =
        grid(from, to, start).flatMap { it.filterNotNull() }

    /** A contiguous day list, used by the per-habit completion card. */
    fun contiguous(start: LocalDate, end: LocalDate): List<LocalDate> {
        if (start > end) return emptyList()
        val out = mutableListOf<LocalDate>()
        var day = start
        while (!day.isAfter(end)) {
            out.add(day)
            day = day.plusDays(1)
        }
        return out
    }
}

/**
 * Habit-day tallies — the one place a completion rate is defined.
 *
 * A day is *due* when the habit was scheduled that weekday **and** was already tracked
 * (`Achievements.firstTrackedDay`). Both halves matter, and each was a bug before it lived here:
 * treating creation as the start reports 614% for backfilled history, and counting raw calendar
 * days reports `8/64` for a habit ten days old. Completions logged on days the habit wasn't
 * scheduled are deliberately excluded from both sides — they're a bonus, not a fraction of a day
 * that was never due.
 */
object HabitDays {
    data class Tally(val due: Int, val done: Int) {
        val rate: Double get() = if (due > 0) done.toDouble() / due.toDouble() else 0.0
    }

    fun tally(habits: List<Habit>, days: List<LocalDate>, clock: HabitsClock): Tally {
        var due = 0
        var done = 0
        val tracked = habits.associateWith { Achievements.firstTrackedDay(it, clock) }
        val doneDays = habits.associate { it.id to it.completions.map { c -> c.day }.toSet() }
        for (day in days) {
            val weekday = Streaks.weekdayIndex(day)
            for (habit in habits) {
                if (!habit.scheduleDays.contains(weekday)) continue
                if (tracked.getValue(habit) > day) continue
                due += 1
                if (doneDays[habit.id]?.contains(day) == true) done += 1
            }
        }
        return Tally(due, done)
    }

    fun rate(tally: Tally): Double = tally.rate
}
