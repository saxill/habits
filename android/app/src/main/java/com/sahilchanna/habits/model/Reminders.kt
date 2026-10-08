package com.sahilchanna.habits.model

import com.sahilchanna.habits.data.Habit
import com.sahilchanna.habits.data.HabitsGraph
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime

/**
 * The arithmetic behind the reminders, with nothing that talks to a notification manager.
 *
 * Every decision worth arguing about — which days a habit is reminded on, which reminders are
 * already moot because the habit is ticked off, which water slots are still ahead of now, and what a
 * glass tally reads — lives here, where a unit test can pin it down. The receivers next door only
 * carry these answers to `AlarmManager` and the notification builder.
 */
object Reminders {

    /**
     * An occurrence is scheduled as a concrete date for each of the next few days rather than as a
     * repeating weekly alarm.
     *
     * A repeating alarm is cheaper and was the first thing tried, but it cannot be skipped: a habit
     * already ticked off still gets buzzed, and the OS offers no way to withdraw just today's
     * occurrence. Concrete dates can be filtered at sync time, which is why "remind me at 08:00"
     * goes quiet on a morning the habit is done. The window is re-armed every time the app comes
     * forward.
     *
     * Android hands out a much larger alarm budget than iOS's 64 pending notifications, but the
     * window is kept small for the same reason it is on iOS: fewer stale alarms to sweep, and the
     * "already done today" filter only has to look a few days ahead to be useful.
     */
    const val LOOKAHEAD_DAYS = 7

    /** Alarm ids are allocated from here; the offset keeps habit and water alarms from colliding. */
    private const val HABIT_ID_BASE = 1000

    data class Occurrence(val habit: Habit, val day: LocalDate, val fire: Instant)

    /**
     * Every reminder worth scheduling in the lookahead window, soonest first.
     *
     * `completionsByHabit` is passed in rather than read off the habits so the caller can build it
     * once from a graph and the function stays pure.
     */
    fun habitOccurrences(
        habits: List<Habit>,
        completionsByHabit: Map<String, Set<LocalDate>>,
        now: Instant,
        clock: HabitsClock,
    ): List<Occurrence> {
        val today = clock.today()
        val out = mutableListOf<Occurrence>()

        for (habit in habits) {
            val minutes = habit.reminderMinutesFromMidnight ?: continue
            val doneDays = completionsByHabit[habit.id] ?: emptySet()

            for (offset in 0 until LOOKAHEAD_DAYS) {
                val day = today.plusDays(offset.toLong())
                if (clock.weekdayIndex(day) !in habit.scheduleDays) continue
                // Today's nudge is pointless once the habit is ticked off — and the whole reason
                // this builds concrete dates instead of one repeating alarm.
                if (day in doneDays) continue
                val fire = clock.instantAt(day, minutes)
                if (!fire.isAfter(now)) continue
                out.add(Occurrence(habit, day, fire))
            }
        }
        return out.sortedBy { it.fire }
    }

    /**
     * Puts the habit occurrences onto alarm ids, soonest first.
     *
     * The two schedules share one id space (and, on Android, one limited budget of exact alarms), so
     * this is where they are reconciled: water takes its ids first because a hydration nudge that
     * quietly stops arriving is far harder to notice than a missing habit reminder.
     */
    fun habitAlarmId(index: Int): Int = HABIT_ID_BASE + index

    // MARK: - Water

    /** The one habit the water reminders count against, if any. */
    fun isWaterHabit(habit: Habit): Boolean {
        // Check-off only. A *timed* habit keeps seconds in `Completion.value`, and this feature
        // reads that field as a glass tally — so a timed habit that happened to be called "water"
        // would have its reminder claim it had logged 1,800 glasses.
        if (habit.type != HabitType.CHECKBOX) return false
        if (habit.icon == "drop") return true
        val n = habit.name.lowercase()
        return n.contains("water") || n.contains("hydrat")
    }

    fun waterHabit(habits: List<Habit>): Habit? =
        // Drop icon first: the surest signal, and it wins even if an earlier habit name-matches.
        habits.firstOrNull { it.icon == "drop" && it.type == HabitType.CHECKBOX }
            ?: habits.firstOrNull { isWaterHabit(it) }

    fun waterHabit(graph: HabitsGraph): Habit? = waterHabit(graph.allHabits)

    /** Glasses logged for a day — the tally carried in the day's completion `value`. */
    fun glasses(habit: Habit?, day: LocalDate): Int = habit?.completion(day)?.value?.toInt() ?: 0

    /** Glasses a full day is worth, used for the "N/8" line in the reminder body. */
    const val WATER_GOAL = 8

    const val WATER_LOOKAHEAD_DAYS = 2

    val INTERVAL_CHOICES = listOf(30, 60, 120, 180)

    data class WindowPreset(val startHour: Int, val endHour: Int, val label: String)

    val WINDOW_PRESETS = listOf(
        WindowPreset(8, 20, "08–20"),
        WindowPreset(9, 21, "09–21"),
        WindowPreset(10, 22, "10–22"),
        WindowPreset(7, 19, "07–19"),
    )

    /**
     * The reminder times across the waking-hours window, inclusive of the end hour.
     *
     * Minutes from midnight rather than a `LocalTime`, because the callers subtract them from the
     * current time to decide what is still ahead; a time-of-day object would have to be reassembled
     * on a specific date for every comparison.
     */
    fun waterSlots(startHour: Int, endHour: Int, intervalMinutes: Int): List<Int> {
        // The floor of 15 minutes guards against a hand-edited preference that would otherwise
        // produce hundreds of alarms and wedge the scheduler.
        if (endHour <= startHour || intervalMinutes < 15) return emptyList()
        val out = mutableListOf<Int>()
        var minutes = startHour * 60
        while (minutes <= endHour * 60) {
            out.add(minutes)
            minutes += intervalMinutes
        }
        return out
    }

    data class WaterOccurrence(val day: LocalDate, val minutes: Int, val fire: Instant)

    /**
     * The water reminders still ahead of `now` across the lookahead window.
     *
     * Each day's occurrences are returned together with that day's glass tally, so the reminder
     * quotes the count for the day it is *for* — zero for tomorrow until the window is rebuilt,
     * never the count frozen in when yesterday's schedule was last added.
     */
    fun waterOccurrences(
        habit: Habit?,
        startHour: Int,
        endHour: Int,
        intervalMinutes: Int,
        now: Instant,
        clock: HabitsClock,
    ): List<WaterOccurrence> {
        val slots = waterSlots(startHour, endHour, intervalMinutes)
        if (slots.isEmpty()) return emptyList()

        val today = clock.today()
        val out = mutableListOf<WaterOccurrence>()
        for (offset in 0 until WATER_LOOKAHEAD_DAYS) {
            val day = today.plusDays(offset.toLong())
            for (minutes in slots) {
                val fire = clock.instantAt(day, minutes)
                if (!fire.isAfter(now)) continue
                out.add(WaterOccurrence(day, minutes, fire))
            }
        }
        return out.sortedBy { it.fire }
    }

    /** Formats minutes-from-midnight the way the settings screen shows a slot ("08:30"). */
    fun slotLabel(minutes: Int): String = LocalTime.of(minutes / 60, minutes % 60)
        .let { "%02d:%02d".format(it.hour, it.minute) }
}
