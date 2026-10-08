package com.sahilchanna.habits.notifications

import android.content.Context
import androidx.glance.appwidget.updateAll
import com.sahilchanna.habits.data.HabitsGraph
import com.sahilchanna.habits.data.HabitsSideEffects
import com.sahilchanna.habits.model.HabitsSnapshot

/**
 * What a change to the store owes the rest of the system: the widgets, the timer notification and
 * the reminder alarms.
 *
 * The reminder re-arm is skipped when nothing about the schedule changed. It is tempting to treat
 * "publish" and "reschedule" as the same event, but every tap publishes, and cancelling and
 * re-arming a few dozen alarms on every checkbox tap is real work on a phone that is often on
 * battery — and it makes the alarms jitter. A fingerprint of the scheduled occurrences is enough to
 * tell the two cases apart.
 */
class RemindersSideEffects(context: Context) : HabitsSideEffects {

    private val appContext = context.applicationContext

    override suspend fun didPublish(snapshot: HabitsSnapshot, graph: HabitsGraph) {
        val clock = com.sahilchanna.habits.HabitsRuntime.clock(appContext)
        val settings = com.sahilchanna.habits.HabitsRuntime.settings(appContext)

        // The timer notification is always refreshed: its content is the live elapsed time and
        // today's progress, both of which can change without the schedule moving at all.
        runCatching { TimerNotifications.refreshAll(appContext, graph, clock, settings) }

        // This is the iOS `WidgetCenter.reloadAllTimelines()` in port. Glance has no push, so the
        // snapshot reaching a widget is this call and nothing else — without it a placed widget
        // would sit on whatever it rendered when it was first added.
        runCatching { com.sahilchanna.habits.widgets.TodayWidget().updateAll(appContext) }
        runCatching { com.sahilchanna.habits.widgets.TodaySmallWidget().updateAll(appContext) }

        val fingerprint = fingerprint(graph, settings, clock)
        if (fingerprint != lastFingerprint) {
            runCatching { ReminderScheduler.reschedule(appContext, graph, settings, clock) }
            lastFingerprint = fingerprint
        }
    }

    override suspend fun habitDeleted(habitId: String) {
        runCatching { TimerNotifications.cancel(appContext, habitId) }
        runCatching { ReminderScheduler.cancelHabit(appContext, habitId) }
        // The schedule lost a habit, so the next publish must re-arm rather than trust the
        // fingerprint it computed before the deletion.
        lastFingerprint = null
    }

    /**
     * A cheap stand-in for "the alarm set": the habit ids with reminders, their days, and the water
     * window. Two schedules with the same fingerprint would arm the same alarms, so there is nothing
     * to do when it is unchanged.
     */
    private fun fingerprint(
        graph: HabitsGraph,
        settings: com.sahilchanna.habits.data.Settings,
        clock: com.sahilchanna.habits.model.HabitsClock,
    ): String {
        val now = clock.now()
        val byHabit = graph.habits.associate { it.id to it.completions.map { c -> c.day }.toSet() }
        val habits = com.sahilchanna.habits.model.Reminders.habitOccurrences(graph.habits, byHabit, now, clock)
            .joinToString("|") { "${it.habit.id}@${it.fire.epochSecond}" }
        val water = if (!settings.waterRemindersEnabled) {
            "off"
        } else {
            "${settings.waterStartHour}-${settings.waterEndHour}-${settings.waterIntervalMinutes}"
        }
        return "$habits#$water"
    }

    private companion object {
        /** In memory only: a fresh process re-arms everything on its first publish anyway. */
        var lastFingerprint: String? = null
    }
}

/**
 * The notification router's Android equivalent.
 *
 * iOS needs a `UNUserNotificationCenterDelegate` to turn a tapped notification into a screen; the
 * Android equivalent is that every notification's content intent opens `MainActivity` — so there is
 * nothing to route. It is kept as a named object anyway, because the categories still have to be
 * registered before any reminder is armed, and doing it in one place beats doing it in three.
 */
object NotificationRouter {
    fun install(context: Context) {
        TimerNotifications.ensureChannels(context)
    }
}
