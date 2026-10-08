package com.sahilchanna.habits.data

import com.sahilchanna.habits.model.DayReset
import com.sahilchanna.habits.model.HabitsClock
import com.sahilchanna.habits.model.HabitsSnapshot
import com.sahilchanna.habits.model.HabitType
import com.sahilchanna.habits.model.logGlassNow
import kotlinx.coroutines.flow.Flow
import java.time.Instant
import java.time.LocalDate

/**
 * The things a user action has to do *besides* writing to the store: refresh the widgets, rebuild
 * the reminder schedule, update or clear the running-timer notification.
 *
 * An interface rather than the notification code called directly, so the mutation logic can be
 * exercised in a unit test with a no-op implementation — and so the repository has no dependency on
 * Android's notification stack, which is what keeps `./gradlew test` free of a device.
 */
interface HabitsSideEffects {
    /** Called after every publish with the freshly-built snapshot. */
    suspend fun didPublish(snapshot: HabitsSnapshot, graph: HabitsGraph)

    /** A habit is gone — its reminders must be cancelled so it cannot buzz from the grave. */
    suspend fun habitDeleted(habitId: String)

    /** An install has no widgets to refresh and no alarms to re-arm. */
    object None : HabitsSideEffects {
        override suspend fun didPublish(snapshot: HabitsSnapshot, graph: HabitsGraph) = Unit
        override suspend fun habitDeleted(habitId: String) = Unit
    }
}

/**
 * The one place the app writes to the store.
 *
 * Every mutation follows the same shape: change the store, then publish — because the snapshot is
 * the widget's whole view of the world and a change that is not published has not happened as far
 * as the home screen is concerned. Screens hold a `HabitsGraph` loaded from `observeGraph()`; the
 * repository's job is to keep that graph and the snapshot from drifting apart.
 */
class HabitsRepository(
    private val store: HabitsStore,
    private val storage: Storage,
    val clock: HabitsClock,
    val settings: Settings,
    private val colors: (String) -> com.sahilchanna.habits.model.SnapshotBuilder.Colors,
    private val sideEffects: HabitsSideEffects = HabitsSideEffects.None,
) {
    val publisher = SnapshotPublisher(store, clock, storage, colors) { settings.themeId }

    fun observeGraph(): Flow<HabitsGraph> = store.observeGraph()

    suspend fun loadGraph(): HabitsGraph = store.loadGraph()

    /**
     * Folds in anything queued from a widget or a notification, then republishes.
     *
     * Called on every app foreground and after every mutation: the queue can only be drained by the
     * process that owns the database, and the app is that process.
     */
    suspend fun refresh(graph: HabitsGraph): HabitsSnapshot {
        val snapshot = publisher.publish(graph)
        sideEffects.didPublish(snapshot, graph)
        return snapshot
    }

    // MARK: - Habits

    /** Records one habit done for a day. The one-per-day invariant is enforced here, not by luck. */
    suspend fun complete(habit: Habit, day: LocalDate, value: Double = 1.0, source: String = "manual") {
        if (habit.completion(day) != null) return
        val created = Completion.of(habit.id, day, clock.now(), value, source)
        created.habit = habit
        habit.completions.add(created)
        store.insertCompletion(created)
    }

    /**
     * The habit row's tap.
     *
     * A running timer checked off logs the elapsed seconds rather than a bare 1 — that is what makes
     * the timed habit's history worth looking at, and it is the same rule the widget's toggle
     * applies, so the two never disagree.
     */
    suspend fun toggle(habit: Habit, day: LocalDate, graph: HabitsGraph) {
        val existing = habit.completion(day)
        if (existing != null) {
            store.deleteCompletion(existing.id)
            habit.completions.removeAll { it.id == existing.id }
            if (habit.startedAt != null && clock.dayOf(habit.startedAt!!) == day) {
                habit.clearTimer()
                store.upsertHabit(habit)
            }
        } else {
            // Past days can be corrected, never completed: a tick is stamped with the moment it was
            // made, so one placed on yesterday reads as "done that day" while being a lie.
            if (day != clock.today()) return
            if (habit.type == HabitType.TIMED && habit.startedAt != null) {
                val elapsed = habit.elapsedSeconds(clock.now())
                habit.clearTimer()
                store.upsertHabit(habit)
                complete(habit, day, elapsed.toDouble(), source = "timer")
            } else {
                complete(habit, day)
            }
        }
        refresh(graph)
    }

    suspend fun logGlass(habit: Habit, day: LocalDate, count: Int = 1, graph: HabitsGraph) {
        logGlassNow(store, habit, day, clock.now(), count)
        refresh(graph)
    }

    suspend fun startTimer(habit: Habit, graph: HabitsGraph) {
        habit.startTimer(clock.now())
        store.upsertHabit(habit)
        refresh(graph)
    }

    /** Pause/resume. Not a publish on its own — the timer notification reads the habit directly —
     * but the widget's running line says "paused", so the snapshot is refreshed too. */
    suspend fun togglePause(habit: Habit, graph: HabitsGraph) {
        habit.togglePause(clock.now())
        store.upsertHabit(habit)
        refresh(graph)
    }

    /** Ends a run without logging it. */
    suspend fun discardTimer(habit: Habit, graph: HabitsGraph) {
        habit.clearTimer()
        store.upsertHabit(habit)
        refresh(graph)
    }

    // MARK: - Editing

    suspend fun saveHabit(habit: Habit, graph: HabitsGraph) {
        store.upsertHabit(habit)
        refresh(graph)
    }

    suspend fun deleteHabit(habit: Habit, graph: HabitsGraph) {
        store.deleteHabit(habit.id)
        habit.routine?.habits?.removeAll { it.id == habit.id }
        // Reminders are cancelled by id, not swept by a prefix: an alarm already armed for this
        // habit is in the system's queue, not in the store, and only this call can reach it.
        sideEffects.habitDeleted(habit.id)
        refresh(graph)
    }

    suspend fun saveRoutine(routine: Routine, graph: HabitsGraph) {
        store.upsertRoutine(routine)
        refresh(graph)
    }

    // MARK: - Day reset

    /**
     * Clears a day and hands back the receipt the undo needs.
     *
     * The undo is the caller's to hold — a screen keeps it for as long as it offers the button —
     * which is why the dropped completions are returned rather than stashed somewhere in here.
     */
    suspend fun reset(day: LocalDate, graph: HabitsGraph): List<DayReset.Dropped> {
        val dropped = DayReset.reset(store, graph, day, clock)
        refresh(graph)
        return dropped
    }

    suspend fun restore(dropped: List<DayReset.Dropped>, graph: HabitsGraph) {
        if (dropped.isEmpty()) return
        DayReset.restore(store, graph, dropped)
        refresh(graph)
    }

    /** Publishes the snapshot without draining the pending queue — used when entering the
     * background, where there is no UI left to reflect a queue change and the point is simply to
     * leave the widget with the freshest picture. */
    suspend fun publishOnly(graph: HabitsGraph) {
        val snapshot = com.sahilchanna.habits.model.SnapshotBuilder.build(graph, clock, colors(settings.themeId))
        com.sahilchanna.habits.model.Snapshots.save(storage, snapshot)
        sideEffects.didPublish(snapshot, graph)
    }

    /**
     * A reminder setting changed.
     *
     * The store has not changed, so nothing needs rebuilding — but the alarms were built from the
     * old window/interval and have to be replaced, which is the side effects' job. Routed through
     * the same publish path so there is one place a schedule is re-armed.
     */
    suspend fun onRemindersChanged(graph: HabitsGraph) {
        publishOnly(graph)
    }

    fun now(): Instant = clock.now()
}
