package com.sahilchanna.habits.notifications

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import com.sahilchanna.habits.data.HabitsGraph
import com.sahilchanna.habits.data.HabitsStore
import com.sahilchanna.habits.data.Settings
import com.sahilchanna.habits.model.HabitsClock
import com.sahilchanna.habits.model.Reminders
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json

/**
 * The reminder schedule, on `AlarmManager`.
 *
 * iOS builds a rolling window of *concrete dates* rather than a repeating trigger, so a reminder
 * for a habit already ticked off can be skipped. Android's repeating alarms have the same defect,
 * for the same reason, so the port keeps the same design: the whole window is re-armed whenever the
 * app comes forward or the store changes, which is also what keeps the schedule honest when the
 * window or interval changes.
 *
 * `Reminders` does the arithmetic; everything here is bookkeeping — remembering what was armed so it
 * can be swept, and talking to the system alarm service.
 */
object ReminderScheduler {

    /** Alarm ids for water start here, leaving the habit range clear. */
    const val WATER_ID_BASE = 50000

    /** The one snooze "in 1h" alarm per kind — a deferral is one nudge, not a slot in a day. */
    const val HABIT_SNOOZE_ID = 90001
    const val WATER_SNOOZE_ID = 90002

    private const val KEY_SCHEDULED = "reminders.scheduled.v1"
    private const val KEY_HABIT_TEST_ID = 90003

    private val json = Json { ignoreUnknownKeys = true }

    @Serializable
    data class Armed(val requestCode: Int, val habitId: String?, val kind: String)

    /**
     * Rebuilds every reminder from the stored settings.
     *
     * Safe to call often: everything previously armed is cancelled first, so an edit never leaves
     * the old time behind. That "cancel everything, then re-arm" shape is why the armed set is
     * written down — the system will not tell us which alarms came from here.
     */
    fun reschedule(context: Context) {
        val store: HabitsStore = com.sahilchanna.habits.HabitsRuntime.store(context)
        val settings = com.sahilchanna.habits.HabitsRuntime.settings(context)
        val clock = com.sahilchanna.habits.HabitsRuntime.clock(context)
        val graph = kotlinx.coroutines.runBlocking { store.loadGraph() }
        reschedule(context, graph, settings, clock)
    }

    fun reschedule(context: Context, graph: HabitsGraph, settings: Settings, clock: HabitsClock) {
        val manager = context.getSystemService(AlarmManager::class.java) ?: return
        clearAll(context, manager)

        val now = clock.now()
        val armed = mutableListOf<Armed>()

        // Water first, deliberately. The two schedules share one alarm budget and one id space, and
        // a hydration nudge that quietly stops arriving is far harder to notice than a missing
        // habit reminder — so water takes its slots before the habit window fills what is left.
        if (settings.waterRemindersEnabled) {
            val habit = Reminders.waterHabit(graph)
            val occurrences = Reminders.waterOccurrences(
                habit = habit,
                startHour = settings.waterStartHour,
                endHour = settings.waterEndHour,
                intervalMinutes = settings.waterIntervalMinutes,
                now = now,
                clock = clock,
            )
            occurrences.forEachIndexed { index, occurrence ->
                val requestCode = WATER_ID_BASE + index
                arm(context, manager, requestCode, occurrence.fire.toEpochMilli(), ReminderReceiver.waterIntent(context, requestCode))
                armed.add(Armed(requestCode, habit?.id, "water"))
            }
        }

        val byHabit = graph.habits.associate { it.id to it.completions.map { c -> c.day }.toSet() }
        val occurrences = Reminders.habitOccurrences(graph.habits, byHabit, now, clock)
        occurrences.forEachIndexed { index, occurrence ->
            val requestCode = Reminders.habitAlarmId(index)
            arm(
                context,
                manager,
                requestCode,
                occurrence.fire.toEpochMilli(),
                ReminderReceiver.habitIntent(context, requestCode, occurrence.habit.id, occurrence.day),
            )
            armed.add(Armed(requestCode, occurrence.habit.id, "habit"))
        }

        saveArmed(com.sahilchanna.habits.HabitsRuntime.storage(context), armed)
    }

    /** Clears one habit's reminders — used when it is deleted, so a habit that is gone cannot buzz. */
    fun cancelHabit(context: Context, habitId: String) {
        val manager = context.getSystemService(AlarmManager::class.java) ?: return
        val storage = com.sahilchanna.habits.HabitsRuntime.storage(context)
        val (mine, others) = loadArmed(storage).partition { it.habitId == habitId }
        for (entry in mine) cancelArmed(context, manager, entry, habitId)
        saveArmed(storage, others)
    }

    private fun clearAll(context: Context, manager: AlarmManager) {
        val storage = com.sahilchanna.habits.HabitsRuntime.storage(context)
        for (entry in loadArmed(storage)) cancelArmed(context, manager, entry, entry.habitId)
        saveArmed(storage, emptyList())
    }

    /**
     * Cancels one armed alarm.
     *
     * The intent has to match the armed one, and an intent matches on its action, data and
     * component — *not* on its extras. So a habit alarm can be rebuilt here without the day it was
     * armed for, which is what makes the sweep possible at all.
     */
    private fun cancelArmed(context: Context, manager: AlarmManager, entry: Armed, habitId: String?) {
        val intent = when (entry.kind) {
            "water" -> ReminderReceiver.waterIntent(context, entry.requestCode)
            else -> ReminderReceiver.habitIntent(context, entry.requestCode, habitId ?: "", null)
        }
        val pending = PendingIntent.getBroadcast(
            context,
            entry.requestCode,
            intent,
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        )
        if (pending != null) manager.cancel(pending)
    }

    private fun arm(context: Context, manager: AlarmManager, requestCode: Int, atMillis: Long, intent: Intent) {
        val pending = PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        // Exact alarms need a user-granted permission on Android 12+; when it is not held, an
        // inexact alarm still arrives (within a window) rather than nothing arriving at all.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || manager.canScheduleExactAlarms()) {
            manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMillis, pending)
        } else {
            manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMillis, pending)
        }
    }

    /** Arms the "in 1h" snooze for one reminder. */
    fun snooze(context: Context, kind: String) {
        val manager = context.getSystemService(AlarmManager::class.java) ?: return
        val requestCode = if (kind == "water") WATER_SNOOZE_ID else HABIT_SNOOZE_ID
        val intent = ReminderReceiver.snoozeIntent(context, requestCode, kind)
        arm(context, manager, requestCode, System.currentTimeMillis() + 60 * 60 * 1000, intent)
    }

    /** Fires one reminder a few seconds out, so scheduling is checkable in the moment. */
    fun fireTest(context: Context, seconds: Long = 5) {
        val manager = context.getSystemService(AlarmManager::class.java) ?: return
        val intent = ReminderReceiver.testIntent(context, KEY_HABIT_TEST_ID)
        arm(context, manager, KEY_HABIT_TEST_ID, System.currentTimeMillis() + seconds * 1000, intent)
    }

    private fun loadArmed(storage: com.sahilchanna.habits.data.Storage): List<Armed> {
        val raw = storage.getString(KEY_SCHEDULED) ?: return emptyList()
        return runCatching { json.decodeFromString<List<Armed>>(raw) }.getOrDefault(emptyList())
    }

    private fun saveArmed(storage: com.sahilchanna.habits.data.Storage, armed: List<Armed>) {
        runCatching { json.encodeToString(ListSerializer(Armed.serializer()), armed) }
            .onSuccess { storage.putString(KEY_SCHEDULED, it) }
    }
}

/** Re-arms the reminders after a reboot: alarms do not survive one. */
class ReminderBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED && intent.action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        runCatching { ReminderScheduler.reschedule(context) }
    }
}
