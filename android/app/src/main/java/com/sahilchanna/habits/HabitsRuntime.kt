package com.sahilchanna.habits

import android.content.Context
import com.sahilchanna.habits.data.HabitsDatabase
import com.sahilchanna.habits.data.HabitsRepository
import com.sahilchanna.habits.data.HabitsShared
import com.sahilchanna.habits.data.HabitsSideEffects
import com.sahilchanna.habits.data.HabitsStore
import com.sahilchanna.habits.data.RoomHabitsStore
import com.sahilchanna.habits.data.Settings
import com.sahilchanna.habits.model.HabitsClock
import com.sahilchanna.habits.model.SnapshotBuilder
import com.sahilchanna.habits.notifications.RemindersSideEffects
import com.sahilchanna.habits.ui.theme.ThemeStore
import java.time.Clock

/**
 * Builds the app's object graph from a bare `Context`.
 *
 * Receivers, widgets and the app itself all need the same wired-up store, and none of them can be
 * handed one by the others — a notification action fires in a process that may have been started
 * for it alone. Rather than a singleton holder that has to be installed before use (and is then a
 * landmine when something runs first), everything here is constructed on demand from shared
 * preferences and a Room singleton, both of which are already process-wide.
 */
object HabitsRuntime {

    /** The app's one storage, installed on first use so a receiver cannot outrun it. */
    fun storage(context: Context) = HabitsShared.storageOrInstall(context)

    fun settings(context: Context): Settings = Settings(storage(context))

    /** A clock reading its reset hour from preferences, so a change is live everywhere. */
    fun clock(context: Context): HabitsClock = HabitsClock(Clock.systemDefaultZone()) {
        settings(context).dayResetHour
    }

    fun store(context: Context): HabitsStore = RoomHabitsStore.from(HabitsDatabase.get(context))

    /** The theme colors the widget snapshot carries. */
    fun colors(context: Context): (String) -> SnapshotBuilder.Colors = { themeId ->
        val theme = ThemeStore(settings(context)).byId(themeId)
        SnapshotBuilder.Colors(
            background = theme.background,
            foreground = theme.foreground,
            comment = theme.comment,
            accent = theme.habitsAccent,
        )
    }

    /**
     * The repository a background component should use.
     *
     * The side effects are attached here rather than at the call site: a widget tick folded in by a
     * receiver has to re-arm the reminders and clear the timer notification exactly as it would if
     * the app were open, and a caller that forgot would leave a stale alarm behind.
     */
    fun repository(context: Context, effects: HabitsSideEffects = RemindersSideEffects(context)): HabitsRepository =
        HabitsRepository(
            store = store(context),
            storage = storage(context),
            clock = clock(context),
            settings = settings(context),
            colors = colors(context),
            sideEffects = effects,
        )
}
