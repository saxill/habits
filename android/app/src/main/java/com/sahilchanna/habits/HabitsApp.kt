package com.sahilchanna.habits

import android.app.Application
import com.sahilchanna.habits.data.HabitsShared
import com.sahilchanna.habits.data.SeedData
import com.sahilchanna.habits.model.CompletionDayAnchor
import com.sahilchanna.habits.model.DemoHistory
import com.sahilchanna.habits.notifications.NotificationRouter
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * The app's entry point.
 *
 * The work here is the iOS `HabitsApp.init` in port: install the shared storage first (everything
 * else reads it), register the notification channels before any reminder can be armed, seed a fresh
 * install, run the two one-time migrations, then publish and re-arm.
 *
 * It runs on a background scope rather than blocking `onCreate`. A first launch has a database to
 * create, and a `runBlocking` here would be a visible stall before the first frame — the screens
 * observe the store through a `Flow`, so they arrive empty and fill in.
 */
class HabitsApp : Application() {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onCreate() {
        super.onCreate()

        HabitsShared.install(this)
        NotificationRouter.install(this)

        val settings = HabitsRuntime.settings(this)
        val store = HabitsRuntime.store(this)
        val repository = HabitsRuntime.repository(this)
        val clock = HabitsRuntime.clock(this)

        scope.launch {
            runCatching {
                SeedData.seedIfNeeded(store, settings, clock.now())
                // Ordered: the demo sweep removes backfilled completions, and re-anchoring then
                // gives the survivors their calendar day. Reversed, the sweep would compare days
                // that had already been rewritten.
                DemoHistory.removeIfNeeded(store, repository.loadGraph(), settings, clock)
                CompletionDayAnchor.migrateIfNeeded(store, settings, clock)
                // One publish builds the widget snapshot and re-arms the reminders against the
                // state the store is actually in — including whatever a widget queued while the
                // app was closed.
                repository.refresh(store.loadGraph())
            }
        }
    }
}
