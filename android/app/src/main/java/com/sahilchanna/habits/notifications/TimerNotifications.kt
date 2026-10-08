package com.sahilchanna.habits.notifications

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.sahilchanna.habits.MainActivity
import com.sahilchanna.habits.R
import com.sahilchanna.habits.data.Habit
import com.sahilchanna.habits.data.HabitsGraph
import com.sahilchanna.habits.data.Settings
import com.sahilchanna.habits.model.HabitsClock
import com.sahilchanna.habits.model.HabitType
import com.sahilchanna.habits.model.Streaks

/**
 * The ongoing notification that stands in for the iOS Live Activity.
 *
 * Android has no Live Activities and no lock-screen widget, so the running timer has to be visible
 * somewhere or it is invisible: this is an ongoing, non-dismissible notification with a live
 * chronometer, which is the closest the platform offers — and, unlike a live activity, it survives
 * the app being killed.
 *
 * The chronometer is set with `setUsesChronometer` and a *base* instant rather than by the app
 * updating the text every second. That matters: it keeps ticking correctly while the app is not
 * running, so a timer started and then backgrounded still reads the right number.
 */
object TimerNotifications {

    const val CHANNEL_TIMER = "habits.timer"
    const val CHANNEL_REMINDER = "habits.reminders"
    const val CHANNEL_WATER = "habits.water"

    /** The notification id for a habit's running timer, derived so it can be cancelled exactly. */
    fun notificationId(habitId: String): Int = habitId.hashCode()

    fun ensureChannels(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        // Three channels rather than one, because they are three different kinds of interruption:
        // a silent ongoing status line, a reminder you asked for, and a hydration nudge you can
        // turn off without turning off anything else.
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_TIMER, "running timer", NotificationManager.IMPORTANCE_LOW).apply {
                description = "The ongoing notification for a running habit timer"
                setShowBadge(false)
            },
        )
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_REMINDER, "habit reminders", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "A nudge at a habit's own time"
            },
        )
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_WATER, "water reminders", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "Hydration nudges across the day"
            },
        )
    }

    /**
     * Shows (or updates) the running-timer notification.
     *
     * The display switches on the profile screen decide what the line says — a timer, a progress
     * count `3/7`, the habit's name — because the whole point of the ongoing notification is to be
     * readable at a glance, and what is readable differs between people.
     */
    fun show(
        context: Context,
        habit: Habit,
        graph: HabitsGraph,
        clock: HabitsClock,
        settings: Settings,
    ) {
        if (!settings.timerNotificationsEnabled) return
        val manager = NotificationManagerCompat.from(context)
        if (!manager.areNotificationsEnabled()) return

        val now = clock.now()
        val contentIntent = PendingIntent.getActivity(
            context,
            notificationId(habit.id),
            Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = NotificationCompat.Builder(context, CHANNEL_TIMER)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentIntent(contentIntent)
            .setOngoing(true)
            .setSilent(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setShowWhen(false)

        val paused = habit.isPaused

        // The title is the habit, unless the user has asked for a bare status line.
        builder.setContentTitle(
            if (settings.showNameInNotification) "> ${habit.name}" else "> timer",
        )

        val parts = mutableListOf<String>()
        if (settings.showTimerInNotification) {
            parts.add(if (paused) "paused" else "running")
        }
        if (settings.showProgressInNotification) {
            val done = graph.habits.count { it.completion(clock.today()) != null }
            val due = graph.habits.count { it.scheduleDays.contains(clock.weekdayIndex(clock.today())) }
            parts.add("$done/$due today")
        }
        val streak = Streaks.habitStreak(habit, clock.today())
        if (streak > 1) parts.add("${streak}d streak")
        builder.setContentText(parts.joinToString(" · ").ifEmpty { null })

        if (settings.showTimerInNotification && !paused) {
            // The system's own chronometer, counting up from the start instant with the paused
            // seconds subtracted. `setUsesChronometer` is what makes it live without the app
            // pushing an update every second.
            builder.setUsesChronometer(true)
            builder.setWhen(chronometerBase(habit, now.toEpochMilli()))
            if (settings.countDown && habit.targetSeconds > 0) {
                builder.setChronometerCountDown(true)
                builder.setWhen(
                    habit.startedAt!!.toEpochMilli() + habit.targetSeconds * 1000 - habit.pausedSeconds * 1000,
                )
            }
        }

        // Three actions: the two a live activity has (log it, discard it), plus pause, which the
        // notification can offer because it is not constrained to a lock-screen widget's size.
        builder.addAction(
            0,
            if (paused) "resume" else "pause",
            TimerActionReceiver.pendingIntent(context, TimerActionReceiver.ACTION_PAUSE, habit.id),
        )
        builder.addAction(
            0,
            "done",
            TimerActionReceiver.pendingIntent(context, TimerActionReceiver.ACTION_DONE, habit.id),
        )
        builder.addAction(
            0,
            "discard",
            TimerActionReceiver.pendingIntent(context, TimerActionReceiver.ACTION_DISCARD, habit.id),
        )

        runCatching { manager.notify(notificationId(habit.id), builder.build()) }
    }

    /**
     * The chronometer's base instant.
     *
     * `setUsesChronometer(true)` with a base *after* now counts down, and one before now counts up —
     * so the count-down case is expressed as "the instant the target will be reached", which is what
     * Android's own clock app does.
     */
    private fun chronometerBase(habit: Habit, nowMillis: Long): Long {
        val started = habit.startedAt?.toEpochMilli() ?: nowMillis
        return started + habit.pausedSeconds * 1000
    }

    /** Cancels a habit's running notification, including after the habit is deleted. */
    fun cancel(context: Context, habitId: String) {
        NotificationManagerCompat.from(context).cancel(notificationId(habitId))
    }

    /** Re-shows every running timer, or clears the ones whose habit has stopped. */
    fun refreshAll(context: Context, graph: HabitsGraph, clock: HabitsClock, settings: Settings) {
        for (habit in graph.habits) {
            if (habit.type != HabitType.TIMED) continue
            if (habit.startedAt == null) cancel(context, habit.id) else show(context, habit, graph, clock, settings)
        }
    }

    /** True when a habit's notification is worth showing at all. */
    fun isRunning(habit: Habit): Boolean = habit.type == HabitType.TIMED && habit.startedAt != null
}
