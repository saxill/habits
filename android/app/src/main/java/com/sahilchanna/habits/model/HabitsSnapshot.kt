package com.sahilchanna.habits.model

import com.sahilchanna.habits.data.HabitsGraph
import com.sahilchanna.habits.data.HabitsShared
import com.sahilchanna.habits.data.Storage
import kotlinx.serialization.Serializable
import java.time.Instant
import java.time.LocalDate

/**
 * The compact "today" picture the app writes and the widgets render.
 *
 * The widget in the iOS build runs in a separate process and cannot open the store, so the app
 * publishes this to the app group. On Android a Glance widget shares the app's process, so the
 * split is not strictly forced — but it is kept anyway, for two reasons that still hold: a widget
 * must never open the database from its own update path (a slow query there is a frozen home
 * screen), and the snapshot is what lets a widget tap show immediately by editing one flag in
 * place, before the authoritative store state is republished over it.
 */
@Serializable
data class SnapshotHabit(
    val id: String,
    val name: String,
    val icon: String,
    val colorHex: String,
    val isTimed: Boolean,
    val done: Boolean,
    val streak: Int,
)

@Serializable
data class SnapshotRoutine(
    val id: String,
    val name: String,
    val subtitle: String,
    val icon: String,
    val habits: List<SnapshotHabit>,
)

@Serializable
data class HabitsSnapshot(
    val dayEpochDay: Long,
    val generatedAtMillis: Long,
    val routines: List<SnapshotRoutine>,
    val doneCount: Int,
    val totalCount: Int,
    val streak: Int,
    // The active theme's colors travel with the snapshot, so a widget matches the in-app look
    // without the widget having to read preferences and rebuild the theme itself.
    val background: String,
    val foreground: String,
    val comment: String,
    val accent: String,
    val running: Running? = null,
) {
    @Serializable
    data class Running(
        val name: String,
        val startedAtMillis: Long,
        val targetSeconds: Double,
        val colorHex: String,
        /** Non-null while the timer is paused, so the widgets can say so too. */
        val pausedAtMillis: Long? = null,
        /** Seconds already lost to pauses. */
        val pausedSeconds: Double = 0.0,
    )

    val day: LocalDate get() = LocalDate.ofEpochDay(dayEpochDay)
    val generatedAt: Instant get() = Instant.ofEpochMilli(generatedAtMillis)

    /** Flattened habits for the compact widget layouts. */
    val flatHabits: List<SnapshotHabit> get() = routines.flatMap { it.habits }
}

/**
 * Reading and writing the snapshot, plus the two in-place edits that let a widget tap land before
 * the app has republished.
 *
 * Every method takes its `Storage` rather than reaching for the app's global one: the widget code
 * passes the same storage, and a unit test can pass a `MemoryStorage` and check the toggle
 * arithmetic without an Android runtime.
 */
object Snapshots {
    private val json = kotlinx.serialization.json.Json { ignoreUnknownKeys = true }

    /** The synthetic routine id the "unfiled" group carries, so a widget can key off it stably. */
    const val UNFILED_ROUTINE_ID = "unfiled"

    fun save(storage: Storage, snapshot: HabitsSnapshot, key: String = HabitsShared.SNAPSHOT_KEY) {
        runCatching { json.encodeToString(HabitsSnapshot.serializer(), snapshot) }.onSuccess { storage.putString(key, it) }
    }

    fun load(storage: Storage, key: String = HabitsShared.SNAPSHOT_KEY): HabitsSnapshot? {
        val raw = storage.getString(key) ?: return null
        return runCatching { json.decodeFromString<HabitsSnapshot>(raw) }.getOrNull()
    }

    /** Drops the running-timer line — used by the notification's own log/discard buttons. */
    fun clearRunning(storage: Storage, now: Instant, key: String = HabitsShared.SNAPSHOT_KEY) {
        val snap = load(storage, key) ?: return
        if (snap.running == null) return
        save(storage, snap.copy(running = null, generatedAtMillis = now.toEpochMilli()), key)
    }

    /**
     * Flips one habit in place, so a widget tap shows immediately instead of waiting for the app to
     * come forward and republish. The app's next publish overwrites this with the store's state.
     */
    fun applyToggle(storage: Storage, habitId: String, done: Boolean, now: Instant, key: String = HabitsShared.SNAPSHOT_KEY) {
        val snap = load(storage, key) ?: return
        var changed = false
        val routines = snap.routines.map { routine ->
            var touched = false
            val habits = routine.habits.map { habit ->
                if (habit.id != habitId || habit.done == done) return@map habit
                touched = true
                changed = true
                habit.copy(done = done)
            }
            if (touched) routine.copy(habits = habits) else routine
        }
        if (!changed) return
        save(
            storage,
            snap.copy(
                routines = routines,
                // Clamped because the counter is a plain integer carried across a process boundary:
                // a toggle applied twice would otherwise drift it out of range permanently.
                doneCount = (snap.doneCount + if (done) 1 else -1).coerceIn(0, snap.totalCount),
                generatedAtMillis = now.toEpochMilli(),
            ),
            key,
        )
    }

    /** Shown before the app has ever published (fresh install, or the widget gallery preview). */
    fun placeholder(clock: HabitsClock = HabitsClock()): HabitsSnapshot {
        val sample = listOf(
            SnapshotHabit("p1", "stretch", "figure.flexibility", "#00D7C3", isTimed = true, done = true, streak = 6),
            SnapshotHabit("p2", "drink water", "drop", "#5AA7FF", isTimed = false, done = true, streak = 11),
            SnapshotHabit("p3", "read", "book", "#C084FC", isTimed = false, done = false, streak = 4),
            SnapshotHabit("p4", "journal", "square.and.pencil", "#FFB454", isTimed = false, done = false, streak = 0),
        )
        return HabitsSnapshot(
            dayEpochDay = clock.today().toEpochDay(),
            generatedAtMillis = clock.now().toEpochMilli(),
            routines = listOf(
                SnapshotRoutine("pr1", "Morning", "// after waking up", "sun.max", sample),
            ),
            doneCount = 2,
            totalCount = 4,
            streak = 5,
            background = "#0A0A0D",
            foreground = "#E8E8E8",
            comment = "#6E6E73",
            accent = "#FFB454",
            running = null,
        )
    }
}

/**
 * Builds the snapshot from the live store.
 *
 * Kept separate from the serialization above because it is the part that decides what a widget
 * shows — which habits count toward today, which streak to display, which timer gets the single
 * "running" line when several are going at once.
 */
object SnapshotBuilder {

    /**
     * The theme colors the snapshot carries. Passed in rather than looked up here so the builder
     * has no opinion about where the active theme is stored.
     */
    data class Colors(val background: String, val foreground: String, val comment: String, val accent: String)

    fun build(
        graph: HabitsGraph,
        clock: HabitsClock,
        colors: Colors,
        pausedSecondsOf: (com.sahilchanna.habits.data.Habit) -> Double = { it.pausedSeconds.toDouble() },
    ): HabitsSnapshot {
        val day = clock.today()
        val weekday = clock.weekdayIndex(day)

        var done = 0
        var total = 0

        // Habits filed under "none" live in no routine, so without this pass they would vanish from
        // every widget while still counting in stats and reminders.
        fun snapHabit(habit: com.sahilchanna.habits.data.Habit): SnapshotHabit? {
            // A habit is only in today's widget if today is one of its days: a Mon/Wed/Fri habit
            // must not sit permanently unticked on a Sunday and drag the day's ratio down.
            if (weekday !in habit.scheduleDays) return null
            val isDone = habit.completion(day) != null
            if (isDone) done += 1
            total += 1
            return SnapshotHabit(
                id = habit.id,
                name = habit.name,
                icon = habit.icon,
                colorHex = habit.color.hex,
                isTimed = habit.type == HabitType.TIMED,
                done = isDone,
                streak = Streaks.habitStreak(habit, day),
            )
        }

        val snapRoutines = mutableListOf<SnapshotRoutine>()
        for (routine in graph.routines.sortedBy { it.sortIndex }) {
            val habits = routine.habits
                .sortedBy { it.sortIndex }
                .mapNotNull { snapHabit(it) }
            snapRoutines.add(SnapshotRoutine(routine.id, routine.name, routine.subtitle, routine.icon, habits))
        }

        val unfiled = graph.unfiledHabits.sortedBy { it.sortIndex }
        if (unfiled.isNotEmpty()) {
            snapRoutines.add(
                SnapshotRoutine(
                    id = Snapshots.UNFILED_ROUTINE_ID,
                    name = "unfiled",
                    subtitle = "// no routine",
                    icon = "tray",
                    habits = unfiled.mapNotNull { snapHabit(it) },
                ),
            )
        }

        // Several timers can run at once, one per habit; the widget has room for one line, so the
        // most recently started one wins.
        val runningHabit = graph.allHabits
            .filter { it.startedAt != null }
            .maxByOrNull { it.startedAt ?: Instant.EPOCH }

        val running = runningHabit?.let { habit ->
            val started = habit.startedAt ?: return@let null
            HabitsSnapshot.Running(
                name = habit.name,
                startedAtMillis = started.toEpochMilli(),
                targetSeconds = habit.targetSeconds.toDouble(),
                colorHex = habit.color.hex,
                pausedAtMillis = habit.pausedAt?.toEpochMilli(),
                pausedSeconds = pausedSecondsOf(habit),
            )
        }

        return HabitsSnapshot(
            dayEpochDay = day.toEpochDay(),
            generatedAtMillis = clock.now().toEpochMilli(),
            routines = snapRoutines,
            doneCount = done,
            totalCount = total,
            streak = Streaks.overall(graph.allCompletions, day),
            background = colors.background,
            foreground = colors.foreground,
            comment = colors.comment,
            accent = colors.accent,
            running = running,
        )
    }
}
