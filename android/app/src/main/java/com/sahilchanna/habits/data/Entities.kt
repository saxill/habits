package com.sahilchanna.habits.data

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Ignore
import androidx.room.Index
import androidx.room.PrimaryKey
import com.sahilchanna.habits.model.Elapsed
import com.sahilchanna.habits.model.HabitColor
import com.sahilchanna.habits.model.HabitType
import java.time.Instant
import java.time.LocalDate
import java.util.UUID

fun newId(): String = UUID.randomUUID().toString()

/**
 * A routine — a named group of habits with a comment-style subtitle (`// after waking up`).
 *
 * The `@Ignore` collection is the same shape SwiftData's `@Model` gives the iOS build for free:
 * the entity *is* the model, and its relationship is a live list of the other entities. The
 * repository wires it up after each load (`Graph.assemble`) rather than letting Room hydrate it,
 * because that is the only way one instance of a habit can be shared between its routine, its
 * completions and the screen.
 */
@Entity(tableName = "routines")
class Routine(
    @PrimaryKey val id: String = newId(),
    var name: String = "",
    var subtitle: String = "",
    var icon: String = "sun.max",
    var sortIndex: Int = 0,
) {
    @Ignore
    var habits: MutableList<Habit> = mutableListOf()

    /** How many of this routine's habits are scheduled on a day, and how many are done. */
    fun tally(day: LocalDate, weekday: Int): Pair<Int, Int> {
        val due = habits.filter { it.scheduleDays.contains(weekday) }
        return due.size to due.count { it.completion(day) != null }
    }
}

/**
 * One habit. Timed habits log elapsed seconds against `targetSeconds`; check-off habits log
 * exactly 1. `scheduleRaw` is a comma-joined weekday list (1 = Sun … 7 = Sat) because that is
 * what the iOS store holds and the value travels through the widget snapshot unchanged.
 */
@Entity(
    tableName = "habits",
    foreignKeys = [
        ForeignKey(
            entity = Routine::class,
            parentColumns = ["id"],
            childColumns = ["routineId"],
            onDelete = ForeignKey.SET_NULL,
        ),
    ],
    indices = [Index("routineId")],
)
class Habit(
    @PrimaryKey val id: String = newId(),
    var name: String = "",
    var icon: String = "circle",
    var colorRaw: String = HabitColor.DEFAULT.raw,
    var typeRaw: String = HabitType.CHECKBOX.raw,
    /** Comment-style subtitle, e.g. `// 10 min`. */
    var comment: String = "",
    /** Timed habits: target in seconds. */
    var targetSeconds: Long = 0,
    var scheduleRaw: String = "1,2,3,4,5,6,7",
    var reminderMinutesFromMidnight: Int? = null,
    var sortIndex: Int = 0,
    var createdAt: Instant = Instant.EPOCH,
    /** Running timer for timed habits (null = not running). */
    var startedAt: Instant? = null,
    /** Set while the running timer is paused; `startedAt` stays put so resuming is exact. */
    var pausedAt: Instant? = null,
    /** Seconds lost to pauses so far, subtracted from the wall-clock elapsed time. */
    var pausedSeconds: Long = 0,
    @ColumnInfo(name = "routineId") var routineId: String? = null,
) {
    /** Filled by `Graph.assemble`, never by Room. */
    @Ignore
    var completions: MutableList<Completion> = mutableListOf()

    @Ignore
    var routine: Routine? = null

    var type: HabitType
        get() = HabitType.from(typeRaw)
        set(value) {
            typeRaw = value.raw
        }

    var color: HabitColor
        get() = HabitColor.from(colorRaw)
        set(value) {
            colorRaw = value.raw
        }

    var scheduleDays: Set<Int>
        get() = scheduleRaw.split(",").mapNotNull { it.trim().toIntOrNull() }.toSet()
        set(value) {
            scheduleRaw = value.sorted().joinToString(",")
        }

    /** `// 10 min` for a timed habit with a target, else the habit's own comment. */
    val targetLabel: String
        get() = if (type == HabitType.TIMED && targetSeconds > 0) Elapsed.targetLabel(targetSeconds) else comment

    /** Today's completion, if any — the one-per-habit-per-day invariant every stat rests on. */
    fun completion(day: LocalDate): Completion? = completions.firstOrNull { it.day == day }

    fun completion(id: String): Completion? = completions.firstOrNull { it.id == id }

    val isPaused: Boolean get() = startedAt != null && pausedAt != null

    fun elapsedSeconds(now: Instant): Long =
        Elapsed.seconds(startedAt, pausedAt, pausedSeconds, now)

    /** `01:23` / `1:02:03`, pauses excluded. */
    fun formattedElapsed(now: Instant): String = Elapsed.short(elapsedSeconds(now))

    /** `hh:mm:ss` of the same, for the ongoing timer notification. */
    fun formattedElapsedLong(now: Instant): String = Elapsed.long(elapsedSeconds(now))

    fun pauseTimer(now: Instant) {
        if (startedAt == null || pausedAt != null) return
        pausedAt = now
    }

    /** Starts (or restarts) the timer, clearing any previous pause accounting. */
    fun startTimer(now: Instant) {
        startedAt = now
        pausedAt = null
        pausedSeconds = 0
    }

    fun resumeTimer(now: Instant) {
        val paused = pausedAt ?: return
        pausedSeconds += (now.epochSecond - paused.epochSecond).coerceAtLeast(0)
        pausedAt = null
    }

    fun togglePause(now: Instant) {
        if (isPaused) resumeTimer(now) else pauseTimer(now)
    }

    /** Clears the running timer, including its accumulated pause time. */
    fun clearTimer() {
        startedAt = null
        pausedAt = null
        pausedSeconds = 0
    }
}

/**
 * One habit's completion of one day.
 *
 * The day is stored as an epoch day — a calendar date — which is what makes it immune to the
 * time-zone drift the iOS store has to anchor at noon to avoid (`Date.dayAnchor`). `legacyDayMillis`
 * is only ever non-null on rows written by a build that stored the day as a local-midnight
 * instant; `CompletionDayAnchor.migrateIfNeeded` folds those into the calendar day once.
 */
@Entity(
    tableName = "completions",
    foreignKeys = [
        ForeignKey(
            entity = Habit::class,
            parentColumns = ["id"],
            childColumns = ["habitId"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
    indices = [Index("habitId"), Index("dayEpochDay")],
)
class Completion(
    @PrimaryKey val id: String = newId(),
    @ColumnInfo(name = "habitId") var habitId: String? = null,
    var dayEpochDay: Long = 0,
    /** Wall-clock timestamp of the tap. */
    var completedAt: Instant = Instant.EPOCH,
    /** checkbox: 1; timed: elapsed seconds; water: the glass tally. */
    var value: Double = 1.0,
    var sourceRaw: String = "manual",
    var legacyDayMillis: Long? = null,
) {
    @Ignore
    var habit: Habit? = null

    /** The calendar day this completion belongs to. */
    var day: LocalDate
        get() = LocalDate.ofEpochDay(dayEpochDay)
        set(value) {
            dayEpochDay = value.toEpochDay()
        }

    var source: String
        get() = sourceRaw
        set(value) {
            sourceRaw = value
        }

    companion object {
        /**
         * The only way new completions should be built, so no caller can forget to derive the
         * calendar day from the habit's day-reset rule.
         */
        fun of(habitId: String?, day: LocalDate, completedAt: Instant, value: Double, source: String = "manual") =
            Completion(
                habitId = habitId,
                dayEpochDay = day.toEpochDay(),
                completedAt = completedAt,
                value = value,
                sourceRaw = source,
            )
    }
}
