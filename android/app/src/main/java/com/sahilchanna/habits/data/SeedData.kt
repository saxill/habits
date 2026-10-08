package com.sahilchanna.habits.data

import com.sahilchanna.habits.model.HabitColor
import com.sahilchanna.habits.model.HabitType

/**
 * The starter routines and habits a first launch gets.
 *
 * No history: every tick in the app is one you made. (An early iOS build backfilled nine days of
 * made-up completions here; `DemoHistory` exists to take those back, and this seed deliberately
 * does not recreate them.)
 *
 * The icon strings are SF Symbol names, kept verbatim from the iOS seed rather than translated to
 * Android drawables at the point of storage. They are the user's data — a habit's icon travels
 * through the widget snapshot and any future export — and a name is exactly as good a key on
 * Android: the UI owns the mapping to a glyph and falls back to a monospace letter for a name it
 * does not know.
 */
object SeedData {

    /** The username a fresh install starts with, matching the iOS seed. */
    const val DEFAULT_USERNAME = "sahil"

    /**
     * Inserts the starters if the store has never been seeded. Returns true when it wrote anything.
     *
     * Marking `seeded` and `demoHistoryRemoved` together is the iOS behaviour and it is deliberate:
     * a fresh install has nothing for the demo sweep to find, and setting the flag here is what
     * stops the sweep from re-scanning on every subsequent launch.
     */
    suspend fun seedIfNeeded(store: HabitsStore, settings: Settings, now: java.time.Instant): Boolean {
        if (settings.seeded) return false
        settings.seeded = true
        settings.demoHistoryRemoved = true
        settings.username = DEFAULT_USERNAME

        val morning = Routine(name = "Morning", subtitle = "// after waking up", icon = "sun.max", sortIndex = 0)
        val deep = Routine(name = "Deep Work", subtitle = "// 09:00 – 13:00", icon = "laptopcomputer", sortIndex = 1)
        val wind = Routine(name = "Wind Down", subtitle = "// before sleep", icon = "moon.stars", sortIndex = 2)

        // sortIndex is assigned by hand: the list is a fixed, curated starting point, and leaving
        // them all at zero would let the order shift with insertion.
        val stretch = habit("stretch", "figure.flexibility", HabitColor.CYAN, HabitType.TIMED, "// 10 min", 0, 600, morning, now)
        val noPhone = habit("no phone first hour", "iphone.slash", HabitColor.RED, HabitType.CHECKBOX, "// before 08:00", 1, 0, morning, now)
        val water = habit("drink water", "drop", HabitColor.BLUE, HabitType.CHECKBOX, "// 500ml", 2, 0, morning, now)
        val focus = habit("focus block", "brain.head.profile", HabitColor.BLUE, HabitType.TIMED, "// 1h", 0, 3600, deep, now)
        val read = habit("read", "book", HabitColor.PURPLE, HabitType.CHECKBOX, "// 20 pages", 1, 0, deep, now)
        val noScreens = habit("no screens after 22", "moon.zzz", HabitColor.RED, HabitType.CHECKBOX, "// wind-down rule", 0, 0, wind, now)
        val journal = habit("journal", "square.and.pencil", HabitColor.AMBER, HabitType.CHECKBOX, "// 5 min", 1, 0, wind, now)

        for (routine in listOf(morning, deep, wind)) store.upsertRoutine(routine)
        for (h in listOf(stretch, noPhone, water, focus, read, noScreens, journal)) store.upsertHabit(h)
        return true
    }

    private fun habit(
        name: String,
        icon: String,
        color: HabitColor,
        type: HabitType,
        comment: String,
        sortIndex: Int,
        targetSeconds: Long,
        routine: Routine,
        now: java.time.Instant,
    ): Habit = Habit(
        name = name,
        icon = icon,
        colorRaw = color.raw,
        typeRaw = type.raw,
        comment = comment,
        targetSeconds = targetSeconds,
        // Every day by default: a starter habit that silently skipped a weekday would look broken
        // before the user has learned the schedule control exists.
        scheduleRaw = "1,2,3,4,5,6,7",
        sortIndex = sortIndex,
        createdAt = now,
        routineId = routine.id,
    )
}
