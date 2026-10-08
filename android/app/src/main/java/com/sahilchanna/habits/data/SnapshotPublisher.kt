package com.sahilchanna.habits.data

import com.sahilchanna.habits.model.HabitsClock
import com.sahilchanna.habits.model.HabitsSnapshot
import com.sahilchanna.habits.model.PendingToggleApplier
import com.sahilchanna.habits.model.PendingToggleQueue
import com.sahilchanna.habits.model.SnapshotBuilder
import com.sahilchanna.habits.model.Snapshots

/**
 * Builds the widget snapshot from the live store and pushes it to shared storage.
 *
 * Runs before the store's other side effects on purpose: a widget tap is queued rather than written
 * (the widget cannot open the database), so folding the queue in has to happen before the
 * snapshot — and before the reminders, which read the store to decide which nudges are already
 * moot — or they would all act on a state the user has already left behind.
 */
class SnapshotPublisher(
    private val store: HabitsStore,
    private val clock: HabitsClock,
    private val storage: Storage,
    private val colors: (String) -> SnapshotBuilder.Colors,
    private val themeId: () -> String,
) {
    private val applier = PendingToggleApplier(store, clock)
    private val queue = PendingToggleQueue(storage, HabitsShared.PENDING_TOGGLES_KEY)

    /** Folds queued widget/notification taps in, rebuilds the snapshot and stores it. */
    suspend fun publish(graph: HabitsGraph): HabitsSnapshot {
        // Widget taps land here first, so the snapshot below reflects them.
        applier.apply(graph, queue)

        val snapshot = SnapshotBuilder.build(graph, clock, colors(themeId()))
        Snapshots.save(storage, snapshot)
        return snapshot
    }

    /** Drops the running line from the published snapshot, for a notification's discard key. */
    fun clearRunning() {
        Snapshots.clearRunning(storage, clock.now())
    }

    /** Mirrors a widget toggle into the snapshot immediately, before the app republishes. */
    fun applyToggle(habitId: String, done: Boolean) {
        Snapshots.applyToggle(storage, habitId, done, clock.now())
    }
}
