package com.sahilchanna.habits.model

import com.sahilchanna.habits.data.HabitsStore
import com.sahilchanna.habits.data.Settings
import java.time.Instant

/**
 * One-time migration for installs that stored a completion's day as a local-midnight instant.
 *
 * The iOS build had exactly this problem: until 2026-09-28 a completion's `day` was the local
 * midnight of its day, which shifts a day when the device's time zone changes — which is why it now
 * stores noon (`Date.dayAnchor`). This port stores the day as a calendar date and does not have the
 * problem at all, but rows carried over from an older build (or from an iOS backup) still hold a
 * millisecond instant, so they are re-derived once. A row with no legacy value is left alone.
 *
 * Honest caveat: a row written in one zone and migrated in a different one shifts by the zone
 * change, which is exactly the ambiguity the migration removes going forward.
 */
object CompletionDayAnchor {
    /** Returns how many rows moved. */
    suspend fun migrateIfNeeded(store: HabitsStore, settings: Settings, clock: HabitsClock): Int {
        if (settings.completionDaysAnchored) return 0
        settings.completionDaysAnchored = true

        val legacy = store.completions().filter { it.legacyDayMillis != null }
        for (completion in legacy) {
            val millis = completion.legacyDayMillis ?: continue
            store.reanchorCompletion(completion.id, clock.dayOf(Instant.ofEpochMilli(millis)))
        }
        return legacy.size
    }
}
