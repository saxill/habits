package com.sahilchanna.habits.notifications

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.sahilchanna.habits.HabitsRuntime
import com.sahilchanna.habits.MainActivity
import com.sahilchanna.habits.R
import com.sahilchanna.habits.data.Habit
import com.sahilchanna.habits.model.PendingToggleQueue
import com.sahilchanna.habits.model.Reminders
import com.sahilchanna.habits.model.Streaks
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.time.LocalDate

/**
 * Every intent action and extra this app's notifications use, in one place.
 *
 * The receivers match on these strings, so a typo is a notification whose buttons silently do
 * nothing — worth avoiding by having exactly one definition.
 */
object NotificationActions {
    const val ACTION_HABIT_REMINDER = "com.sahilchanna.habits.HABIT_REMINDER"
    const val ACTION_WATER_REMINDER = "com.sahilchanna.habits.WATER_REMINDER"
    const val ACTION_SNOOZE = "com.sahilchanna.habits.SNOOZE"
    const val ACTION_TEST = "com.sahilchanna.habits.REMINDER_TEST"

    const val ACTION_DONE = "com.sahilchanna.habits.HABIT_DONE"
    const val ACTION_LOG_GLASS = "com.sahilchanna.habits.WATER_LOG_GLASS"

    const val ACTION_TIMER_DONE = "com.sahilchanna.habits.TIMER_DONE"
    const val ACTION_TIMER_PAUSE = "com.sahilchanna.habits.TIMER_PAUSE"
    const val ACTION_TIMER_DISCARD = "com.sahilchanna.habits.TIMER_DISCARD"

    const val EXTRA_HABIT_ID = "habitId"
    const val EXTRA_DAY_EPOCH = "dayEpochDay"
    const val EXTRA_KIND = "kind"
    const val EXTRA_REQUEST_CODE = "requestCode"

    const val KIND_HABIT = "habit"
    const val KIND_WATER = "water"
}

/**
 * Shows a habit or water reminder.
 *
 * The notification is built from the store at the moment it fires rather than from the values
 * frozen in when it was armed — that is the whole reason these are concrete one-off alarms instead
 * of repeating triggers: a reminder that fires must quote today's streak and today's glass count,
 * not last week's.
 */
class ReminderReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val kind = intent.getStringExtra(NotificationActions.EXTRA_KIND) ?: NotificationActions.KIND_HABIT
        if (kind == NotificationActions.KIND_WATER) showWater(context) else showHabit(context, intent)
    }

    private fun showHabit(context: Context, intent: Intent) {
        val habitId = intent.getStringExtra(NotificationActions.EXTRA_HABIT_ID) ?: return
        val epoch = intent.getLongExtra(NotificationActions.EXTRA_DAY_EPOCH, Long.MIN_VALUE)
        val day = if (epoch == Long.MIN_VALUE) null else LocalDate.ofEpochDay(epoch)
        val requestCode = intent.getIntExtra(NotificationActions.EXTRA_REQUEST_CODE, habitId.hashCode())

        val graph = runCatching { kotlinx.coroutines.runBlocking { HabitsRuntime.store(context).loadGraph() } }
            .getOrDefault(com.sahilchanna.habits.data.HabitsGraph.EMPTY)
        val habit = graph.habit(habitId) ?: return
        val clock = HabitsRuntime.clock(context)

        if (!notificationsAllowed(context)) return

        val builder = NotificationCompat.Builder(context, TimerNotifications.CHANNEL_REMINDER)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("> ${habit.name}")
            .setContentText(habitBody(habit, clock.today()))
            .setAutoCancel(true)
            .setContentIntent(openApp(context, requestCode))
            .addAction(0, "done", action(context, requestCode, NotificationActions.ACTION_DONE, habitId, day))
            .addAction(0, "in 1h", action(context, requestCode + 7, NotificationActions.ACTION_SNOOZE, habitId, day))

        runCatching { NotificationManagerCompat.from(context).notify(TimerNotifications.notificationId(habitId), builder.build()) }
    }

    private fun showWater(context: Context) {
        val graph = runCatching { kotlinx.coroutines.runBlocking { HabitsRuntime.store(context).loadGraph() } }
            .getOrDefault(com.sahilchanna.habits.data.HabitsGraph.EMPTY)
        val water = Reminders.waterHabit(graph)
        val clock = HabitsRuntime.clock(context)
        if (!notificationsAllowed(context)) return

        val glasses = Reminders.glasses(water, clock.today())
        val builder = NotificationCompat.Builder(context, TimerNotifications.CHANNEL_WATER)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("> drink water")
            .setContentText(
                if (water == null) "// hydration check — grab a glass"
                else "// $glasses/${Reminders.WATER_GOAL} glasses today — log one?",
            )
            .setAutoCancel(true)
            .setContentIntent(openApp(context, 0))
            .addAction(
                0, "log glass",
                action(context, ReminderScheduler.WATER_ID_BASE + 7, NotificationActions.ACTION_LOG_GLASS, water?.id, null),
            )
            .addAction(
                0, "in 1h",
                action(context, ReminderScheduler.WATER_ID_BASE + 8, NotificationActions.ACTION_SNOOZE, water?.id, null, kind = NotificationActions.KIND_WATER),
            )

        runCatching { NotificationManagerCompat.from(context).notify(WATER_NOTIFICATION_ID, builder.build()) }
    }

    /**
     * The reminder's body line.
     *
     * The habit's own comment when it has one, else its routine — and the streak appended only past
     * one day, because "1d streak" is noise on a nudge that is meant to be read at a glance.
     */
    private fun habitBody(habit: Habit, today: LocalDate): String {
        var line = if (habit.comment.isNotEmpty()) {
            habit.comment
        } else {
            habit.routine?.let { "// ${it.name.lowercase()}" } ?: "// scheduled now"
        }
        val streak = Streaks.habitStreak(habit, today)
        if (streak > 1) line += " · ${streak}d streak"
        return line
    }

    private fun notificationsAllowed(context: Context): Boolean =
        NotificationManagerCompat.from(context).areNotificationsEnabled()

    private fun openApp(context: Context, requestCode: Int): PendingIntent = PendingIntent.getActivity(
        context,
        requestCode,
        Intent(context, MainActivity::class.java),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    companion object {
        const val WATER_NOTIFICATION_ID = 90010

        /**
         * The intent that arms a habit reminder.
         *
         * The day travels as an epoch day so the receiver can tell which day the nudge was *for* —
         * and drop a "done" actioned after midnight rather than crediting it to yesterday.
         */
        fun habitIntent(context: Context, requestCode: Int, habitId: String, day: LocalDate?): Intent =
            Intent(context, ReminderReceiver::class.java).apply {
                action = NotificationActions.ACTION_HABIT_REMINDER
                putExtra(NotificationActions.EXTRA_KIND, NotificationActions.KIND_HABIT)
                putExtra(NotificationActions.EXTRA_HABIT_ID, habitId)
                putExtra(NotificationActions.EXTRA_REQUEST_CODE, requestCode)
                if (day != null) putExtra(NotificationActions.EXTRA_DAY_EPOCH, day.toEpochDay())
            }

        fun waterIntent(context: Context, requestCode: Int): Intent =
            Intent(context, ReminderReceiver::class.java).apply {
                action = NotificationActions.ACTION_WATER_REMINDER
                putExtra(NotificationActions.EXTRA_KIND, NotificationActions.KIND_WATER)
                putExtra(NotificationActions.EXTRA_REQUEST_CODE, requestCode)
            }

        fun snoozeIntent(context: Context, requestCode: Int, kind: String): Intent =
            Intent(context, ReminderReceiver::class.java).apply {
                action = NotificationActions.ACTION_SNOOZE
                putExtra(NotificationActions.EXTRA_KIND, kind)
                putExtra(NotificationActions.EXTRA_REQUEST_CODE, requestCode)
            }

        fun testIntent(context: Context, requestCode: Int): Intent =
            Intent(context, ReminderReceiver::class.java).apply {
                action = NotificationActions.ACTION_TEST
                putExtra(NotificationActions.EXTRA_KIND, NotificationActions.KIND_HABIT)
                putExtra(NotificationActions.EXTRA_REQUEST_CODE, requestCode)
            }

        private fun action(
            context: Context,
            requestCode: Int,
            action: String,
            habitId: String?,
            day: LocalDate?,
            kind: String = NotificationActions.KIND_HABIT,
        ): PendingIntent = PendingIntent.getBroadcast(
            context,
            requestCode,
            Intent(context, ReminderActionReceiver::class.java).apply {
                this.action = action
                putExtra(NotificationActions.EXTRA_HABIT_ID, habitId)
                putExtra(NotificationActions.EXTRA_KIND, kind)
                if (day != null) putExtra(NotificationActions.EXTRA_DAY_EPOCH, day.toEpochDay())
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}

/**
 * The buttons on a reminder: done, log glass, snooze.
 *
 * Each writes through the *same* pending-toggle queue the widgets use, so a notification action and
 * a tap in the app are one code path — which is what keeps the two from disagreeing about whether
 * something was logged.
 */
class ReminderActionReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        val appContext = context.applicationContext
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val habitId = intent.getStringExtra(NotificationActions.EXTRA_HABIT_ID)
                val epoch = intent.getLongExtra(NotificationActions.EXTRA_DAY_EPOCH, Long.MIN_VALUE)
                val queue = PendingToggleQueue(HabitsRuntime.storage(appContext), com.sahilchanna.habits.data.HabitsShared.PENDING_TOGGLES_KEY)
                val clock = HabitsRuntime.clock(appContext)

                when (intent.action) {
                    NotificationActions.ACTION_DONE -> {
                        // Dated to the day the reminder was *for*. The applier drops a tick for a
                        // past day, which is the rule that stops a midnight tap from rewriting
                        // yesterday.
                        val day = if (epoch == Long.MIN_VALUE) clock.today() else LocalDate.ofEpochDay(epoch)
                        if (habitId != null) queue.set(habitId, day, done = true, nowMillis = clock.now().toEpochMilli())
                    }

                    NotificationActions.ACTION_LOG_GLASS -> {
                        if (habitId != null) {
                            queue.logGlass(habitId, clock.today(), 1, clock.now().toEpochMilli())
                        }
                    }

                    NotificationActions.ACTION_SNOOZE -> {
                        val kind = intent.getStringExtra(NotificationActions.EXTRA_KIND) ?: NotificationActions.KIND_HABIT
                        ReminderScheduler.snooze(appContext, kind)
                    }
                }

                // Drains the queue and republishes, so the widget shows the tap straight away
                // instead of waiting for the app to next come forward.
                HabitsRuntime.repository(appContext).refresh(HabitsRuntime.store(appContext).loadGraph())
                NotificationManagerCompat.from(appContext).cancel(TimerNotifications.notificationId(habitId ?: ""))
            } catch (_: Throwable) {
                // A notification action that throws has nowhere to report it; the queue write, if
                // it landed, is still applied on the next foreground.
            } finally {
                pending.finish()
            }
        }
    }
}

/**
 * The buttons on the ongoing timer notification.
 *
 * Pause and discard are the two the iOS live activity offers; "done" is the third, and it is the
 * one that matters most — a running timer that can only be stopped from inside the app is exactly
 * the timer people abandon.
 */
class TimerActionReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        val appContext = context.applicationContext
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val habitId = intent.getStringExtra(NotificationActions.EXTRA_HABIT_ID) ?: return@launch
                val clock = HabitsRuntime.clock(appContext)
                val queue = PendingToggleQueue(HabitsRuntime.storage(appContext), com.sahilchanna.habits.data.HabitsShared.PENDING_TOGGLES_KEY)
                val now = clock.now().toEpochMilli()

                when (intent.action) {
                    ACTION_PAUSE -> {
                        // The queued entry carries the *desired* pause state, which is read from the
                        // store here: the receiver cannot know whether the timer is currently paused
                        // without loading it, and the store is the only truth.
                        val graph = HabitsRuntime.store(appContext).loadGraph()
                        val paused = graph.habit(habitId)?.isPaused ?: false
                        queue.setPaused(habitId, paused = !paused, today = clock.today(), nowMillis = now)
                    }

                    ACTION_DONE -> queue.set(habitId, clock.today(), done = true, nowMillis = now)
                    ACTION_DISCARD -> queue.stopTimer(habitId, clock.today(), nowMillis = now)
                }

                HabitsRuntime.repository(appContext).refresh(HabitsRuntime.store(appContext).loadGraph())
                NotificationManagerCompat.from(appContext).cancel(TimerNotifications.notificationId(habitId))
            } catch (_: Throwable) {
                // Same reasoning as the reminder actions: nothing to report to, and the queued
                // write is picked up next time the app runs.
            } finally {
                pending.finish()
            }
        }
    }

    companion object {
        const val ACTION_PAUSE = NotificationActions.ACTION_TIMER_PAUSE
        const val ACTION_DONE = NotificationActions.ACTION_TIMER_DONE
        const val ACTION_DISCARD = NotificationActions.ACTION_TIMER_DISCARD

        fun pendingIntent(context: Context, action: String, habitId: String): PendingIntent =
            PendingIntent.getBroadcast(
                context,
                // Distinct per action and habit, or the three buttons would all map to one intent
                // and the last one registered would win.
                (habitId + action).hashCode(),
                Intent(context, TimerActionReceiver::class.java).apply {
                    this.action = action
                    putExtra(NotificationActions.EXTRA_HABIT_ID, habitId)
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
    }
}
