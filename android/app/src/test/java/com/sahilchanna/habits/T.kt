package com.sahilchanna.habits

import com.sahilchanna.habits.data.Completion
import com.sahilchanna.habits.data.Habit
import com.sahilchanna.habits.data.HabitsGraph
import com.sahilchanna.habits.data.Routine
import com.sahilchanna.habits.model.HabitColor
import com.sahilchanna.habits.model.HabitType
import com.sahilchanna.habits.model.HabitsClock
import java.time.Clock
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/**
 * Helpers shared by the tests.
 *
 * Everything here is deliberately explicit about time: the clock is always a fixed instant in UTC.
 * A test that passes in one zone and fails in another is worse than no test, and half the logic
 * under test is *about* which day something belongs to.
 */
object T {

    val UTC: ZoneId = ZoneId.of("UTC")

    /** A clock pinned to `instant`, in UTC, with an optional day-reset hour. */
    fun clock(instant: String, resetHour: Int = 0): HabitsClock {
        val fixed = Clock.fixed(Instant.parse(instant), UTC)
        return HabitsClock(fixed) { resetHour }
    }

    fun atDay(day: String, hour: Int = 12): Instant = Instant.parse("${day}T%02d:00:00Z".format(hour))

    fun day(value: String): LocalDate = LocalDate.parse(value)

    fun habit(
        id: String = "h1",
        name: String = "stretch",
        icon: String = "circle",
        type: HabitType = HabitType.CHECKBOX,
        color: HabitColor = HabitColor.CYAN,
        comment: String = "",
        targetSeconds: Long = 0,
        scheduleDays: Set<Int> = setOf(1, 2, 3, 4, 5, 6, 7),
        reminderMinutesFromMidnight: Int? = null,
        sortIndex: Int = 0,
        createdAt: Instant = Instant.parse("2026-01-01T00:00:00Z"),
        routine: Routine? = null,
    ): Habit = Habit(
        id = id,
        name = name,
        icon = icon,
        colorRaw = color.raw,
        typeRaw = type.raw,
        comment = comment,
        targetSeconds = targetSeconds,
        scheduleRaw = scheduleDays.sorted().joinToString(","),
        reminderMinutesFromMidnight = reminderMinutesFromMidnight,
        sortIndex = sortIndex,
        createdAt = createdAt,
        routineId = routine?.id,
    ).also { it.routine = routine }

    fun routine(
        id: String = "r1",
        name: String = "Morning",
        subtitle: String = "// after waking up",
        icon: String = "sun.max",
        sortIndex: Int = 0,
        habits: List<Habit> = emptyList(),
    ): Routine = Routine(id = id, name = name, subtitle = subtitle, icon = icon, sortIndex = sortIndex)
        .also { r ->
            r.habits = habits.toMutableList()
            habits.forEach { it.routine = r }
        }

    /** Marks a habit done on a day, wiring both directions of the relationship. */
    fun done(habit: Habit, day: LocalDate, value: Double = 1.0, at: Instant? = null): Completion {
        val completion = Completion.of(habit.id, day, at ?: atDay(day.toString()), value)
        completion.habit = habit
        habit.completions.add(completion)
        return completion
    }

    /** A graph with the relationships wired, built from habits that already carry completions. */
    fun graph(habits: List<Habit>, routines: List<Routine> = emptyList()): HabitsGraph {
        val completions = habits.flatMap { it.completions }
        return HabitsGraph.assemble(routines, habits, completions)
    }
}
