package com.sahilchanna.habits.model

import java.time.LocalDate

/**
 * A habit's elapsed-time formatting, shared by the habit row, the ongoing timer notification
 * and the widget. Kept apart from the entity so it can be tested without a store behind it.
 */
object Elapsed {
    /** Pauses excluded: while paused the clock stops, so this returns the same value whenever it
     *  is asked. */
    fun seconds(startedAt: java.time.Instant?, pausedAt: java.time.Instant?, pausedSeconds: Long, now: java.time.Instant): Long {
        val started = startedAt ?: return 0
        val end = pausedAt ?: now
        return (end.epochSecond - started.epochSecond - pausedSeconds).coerceAtLeast(0)
    }

    /**
     * `01:23` under an hour, `1:02:03` above it — the hour field is dropped under 60 minutes,
     * matching the in-app row. The timer notification and the live-activity replacement show the
     * same shape.
     */
    fun short(seconds: Long): String {
        val s = seconds.coerceAtLeast(0)
        val h = s / 3600
        val m = (s % 3600) / 60
        val sec = s % 60
        return if (h > 0) "%d:%02d:%02d".format(h, m, sec) else "%02d:%02d".format(m, sec)
    }

    /** `hh:mm:ss`, the always-full form a running session is counted in. */
    fun long(seconds: Long): String {
        val s = seconds.coerceAtLeast(0)
        return "%02d:%02d:%02d".format(s / 3600, (s % 3600) / 60, s % 60)
    }

    /** `10 min`, `1h`, `1h30min` — a target, not a running count. */
    fun targetLabel(targetSeconds: Long): String {
        if (targetSeconds <= 0) return ""
        val minutes = targetSeconds / 60
        if (minutes >= 60) {
            val h = minutes / 60
            val r = minutes % 60
            return if (r == 0L) "${h}h" else "${h}h${r}min"
        }
        return "$minutes min"
    }
}

/** A day and the instant it was logged at, for anything that has to report a timestamp. */
data class LoggedMoment(val day: LocalDate, val at: java.time.Instant)
