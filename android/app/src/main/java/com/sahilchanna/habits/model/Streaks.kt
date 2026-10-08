package com.sahilchanna.habits.model

import com.sahilchanna.habits.data.Completion
import com.sahilchanna.habits.data.Habit
import java.time.LocalDate

/**
 * All streak math is derived from Completion history — never stored (PRD §7).
 *
 * Everything here is pure arithmetic over calendar dates, so it needs no clock of its own:
 * "today" is handed in, which is what makes the tests deterministic.
 */
object Streaks {

    /**
     * Consecutive days on which the habit was completed, ending today with a grace window
     * through yesterday: today not done yet does not break a streak.
     */
    fun habitStreak(habit: Habit, today: LocalDate): Int =
        streakOf(habit.completions.map { it.day }, today)

    /** Overall app streak: consecutive days with at least one completion, same today-grace. */
    fun overall(completions: List<Completion>, today: LocalDate): Int =
        streakOf(completions.map { it.day }, today)

    private fun streakOf(days: List<LocalDate>, today: LocalDate): Int {
        val done = days.toSet()
        if (done.isEmpty()) return 0
        // Today not done yet doesn't break the streak — start the walk at today or yesterday.
        var cursor = if (today in done) today else today.minusDays(1)
        var streak = 0
        while (cursor in done) {
            streak += 1
            cursor = cursor.minusDays(1)
        }
        return streak
    }

    /** Best streak ever for one habit (ignores schedule gaps — any completion counts). */
    fun bestStreak(habit: Habit): Int = bestRun(habit.completions.map { it.day })

    /**
     * Longest run of consecutive days with at least one completion, ever.
     *
     * Distinct from `overall`, which measures the streak *as it stands today* and is broken by a
     * single missed day. Lifetime achievements have to ask this instead — "you once held a 30-day
     * streak" must stay true forever, not lapse the moment the current one ends.
     */
    fun bestOverall(completions: List<Completion>): Int = bestRun(completions.map { it.day })

    private fun bestRun(days: List<LocalDate>): Int {
        val sorted = days.distinct().sorted()
        if (sorted.isEmpty()) return 0
        var best = 1
        var run = 1
        for (i in 1 until sorted.size) {
            run = if (sorted[i - 1].plusDays(1) == sorted[i]) run + 1 else 1
            if (run > best) best = run
        }
        return best
    }

    /**
     * Completion ratio (0…1) for one day, or **-1** when nothing was scheduled — the value that
     * drives the week strip's fill bar and the overview heatmap.
     *
     * Habits that did not exist yet are not "scheduled" on a day before their history begins:
     * without this bound a habit created this month marked every earlier day of the week strip as
     * missed.
     */
    fun dayRatio(day: LocalDate, habits: List<Habit>, clock: HabitsClock = HabitsClock()): Double {
        val weekday = weekdayIndex(day)
        val scheduled = habits.filter {
            Achievements.firstTrackedDay(it, clock) <= day && it.scheduleDays.contains(weekday)
        }
        if (scheduled.isEmpty()) return -1.0
        val done = scheduled.count { it.completion(day) != null }
        return done.toDouble() / scheduled.size
    }

    /** Calendar weekday as 1…7 (Sun…Sat), matching the schedule field and `Calendar.weekday`. */
    fun weekdayIndex(day: LocalDate): Int = day.dayOfWeek.value % 7 + 1
}
