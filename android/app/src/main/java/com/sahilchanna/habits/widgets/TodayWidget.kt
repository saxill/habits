package com.sahilchanna.habits.widgets

import android.content.Context
import android.content.Intent
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.LocalContext
import androidx.glance.action.ActionParameters
import androidx.glance.action.actionParametersOf
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.updateAll
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.padding
import androidx.glance.text.FontFamily
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.compose.ui.graphics.Color
import androidx.glance.unit.ColorProvider
import com.sahilchanna.habits.HabitsRuntime
import com.sahilchanna.habits.MainActivity
import com.sahilchanna.habits.data.HabitsShared
import com.sahilchanna.habits.model.HabitsSnapshot
import com.sahilchanna.habits.model.PendingToggleQueue
import com.sahilchanna.habits.model.SnapshotHabit
import com.sahilchanna.habits.model.Snapshots
import com.sahilchanna.habits.ui.theme.parseHex
import java.time.LocalDate

/**
 * The home-screen widgets (§4.4), in two sizes.
 *
 * Android has no lock-screen widget, so the iOS build's small/medium *and* lock-screen families
 * collapse into two home-screen widgets here: a 2×2 that is the glanceable `[3/7]`, and a 4×2 that
 * adds today's remaining habits as tappable rows.
 *
 * Both render from the snapshot the app last published rather than from the database. That is the
 * same contract the iOS widget has, and it is what keeps the widget cheap: rendering is a JSON read
 * and no query at all. It also means a widget can still be showing yesterday until the app next
 * runs — which is why a stale snapshot is labelled `yesterday` and its rows are not tappable.
 */
class TodayWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val snapshot = loadSnapshot(context)
        provideContent { WidgetBody(snapshot = snapshot, showHabits = true) }
    }

    companion object {
        /** One place the snapshot is read, so both sizes and the gallery preview agree. */
        fun loadSnapshot(context: Context): HabitsSnapshot {
            val storage = HabitsRuntime.storage(context)
            return Snapshots.load(storage) ?: Snapshots.placeholder(HabitsRuntime.clock(context))
        }
    }
}

/** The 2×2 size: today's tally, the character bar and the streak. */
class TodaySmallWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val snapshot = TodayWidget.loadSnapshot(context)
        provideContent { WidgetBody(snapshot = snapshot, showHabits = false) }
    }
}

class TodayWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = TodayWidget()
}

class TodaySmallWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = TodaySmallWidget()
}

private val habitIdParam = ActionParameters.Key<String>("habitId")
private val doneParam = ActionParameters.Key<Boolean>("done")

/**
 * The widget's whole picture.
 *
 * Glance has no live timer, so a running habit is reported as the elapsed time *at render*, not as a
 * counting label — the iOS widget's `Text(timerInterval:)` has no equivalent here. That is a real
 * loss, and it is why the widget is redrawn on every publish: the number is at most one publish
 * behind rather than one second behind.
 */
@Composable
private fun WidgetBody(snapshot: HabitsSnapshot, showHabits: Boolean) {
    val context = LocalContext.current
    val accent = ColorProvider(parseHex(snapshot.accent))
    val comment = ColorProvider(parseHex(snapshot.comment))
    val foreground = ColorProvider(parseHex(snapshot.foreground))
    val stale = isStale(snapshot)
    val allDone = snapshot.totalCount > 0 && snapshot.doneCount == snapshot.totalCount

    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .background(ColorProvider(parseHex(snapshot.background)))
            .padding(10.dp)
            .clickable(actionStartActivity(Intent(context, MainActivity::class.java))),
    ) {
        Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(">", style = mono(10, accent, FontWeight.Bold))
            Text(if (stale) " yesterday" else " today", style = mono(10, comment))
            Spacer(GlanceModifier.defaultWeight())
            if (snapshot.streak > 0) {
                Text("▲ ${snapshot.streak}", style = mono(10, ColorProvider(parseHex("#FF9F45"))))
            }
        }

        Text(
            "[${snapshot.doneCount}/${snapshot.totalCount}]",
            style = mono(
                // A fully-done day goes green whatever the theme's accent is: that is the one
                // state on this widget worth shouting about.
                size = if (showHabits) 26 else 30,
                color = if (allDone) ColorProvider(parseHex("#4ADE80")) else accent,
                weight = FontWeight.Bold,
            ),
        )

        Text(progressBar(snapshot), style = mono(11, accent, FontWeight.Bold))

        val running = snapshot.running
        if (running != null) {
            Text("⏱ ${running.name} ${elapsedLabel(running)}", style = mono(9, foreground))
        } else {
            Text("// ${snapshot.totalCount - snapshot.doneCount} left", style = mono(9, comment))
        }

        if (showHabits) {
            Spacer(GlanceModifier.defaultWeight())
            displayedHabits(snapshot).forEach { habit ->
                HabitLine(habit = habit, tappable = !stale)
            }
        }
    }
}

/**
 * One habit row: `[✓] read`, and a tap that toggles it.
 *
 * The tap does not write to the database. The widget can start the process on its own, before the
 * app has any repository, so it records the desired state in the pending-toggle queue and mirrors it
 * into the snapshot to make the tap look immediate; the app folds the queue in on its next publish.
 * That is the same handshake the iOS widget's `ToggleHabitIntent` does.
 */
@Composable
private fun HabitLine(habit: SnapshotHabit, tappable: Boolean) {
    val base = GlanceModifier.fillMaxWidth()
    val modifier = if (tappable) {
        base.clickable(
            actionRunCallback<ToggleHabitAction>(
                actionParametersOf(habitIdParam to habit.id, doneParam to !habit.done),
            ),
        )
    } else {
        base
    }
    Row(modifier = modifier, verticalAlignment = Alignment.CenterVertically) {
        Text(if (habit.done) "[✓]" else "[ ]", style = mono(10, weight = FontWeight.Bold))
        Text(" ${habit.name}", style = mono(10))
    }
}

/** Remaining first, then whatever is left — four lines, the most a medium widget can read. */
private fun displayedHabits(snapshot: HabitsSnapshot): List<SnapshotHabit> {
    val remaining = snapshot.flatHabits.filter { !it.done }
    return (if (remaining.isEmpty()) snapshot.flatHabits else remaining).take(4)
}

/** `▓▓▓▓░░░░` — one cell per habit, filled when done. */
private fun progressBar(snapshot: HabitsSnapshot): String {
    if (snapshot.totalCount <= 0) return "// no habits today"
    val cells = minOf(snapshot.totalCount, 10)
    val filled = Math.round(snapshot.doneCount.toDouble() / snapshot.totalCount * cells).toInt()
    return "▓".repeat(filled) + "░".repeat((cells - filled).coerceAtLeast(0))
}

/**
 * The snapshot is what the app last published, so after midnight it is still yesterday's day.
 *
 * Compared against the device's own date rather than the app's reset-hour-aware clock: a widget
 * should not disagree with the lock screen about what day it is, and the reset hour only shifts the
 * boundary by a few hours at most.
 */
private fun isStale(snapshot: HabitsSnapshot): Boolean = snapshot.day != LocalDate.now()

/**
 * `12:34`, or `1:02:03` past an hour — the running timer, frozen at render time.
 *
 * Paused time is subtracted here rather than left to a live label, because there is no live label:
 * a paused run shows the time it had reached when it was paused.
 */
private fun elapsedLabel(running: HabitsSnapshot.Running): String {
    val end = running.pausedAtMillis ?: System.currentTimeMillis()
    val seconds = ((end - running.startedAtMillis) / 1000.0 - running.pausedSeconds).coerceAtLeast(0.0).toLong()
    return if (seconds >= 3600) {
        "%d:%02d:%02d".format(seconds / 3600, (seconds / 60) % 60, seconds % 60)
    } else {
        "%d:%02d".format(seconds / 60, seconds % 60)
    }
}

/** Monospace at a base size, which is what every line on this widget is. */
private fun mono(
    size: Int,
    color: ColorProvider? = null,
    weight: FontWeight = FontWeight.Normal,
): TextStyle = TextStyle(
    color = color ?: ColorProvider(Color.Unspecified),
    fontSize = size.sp,
    fontWeight = weight,
    fontFamily = FontFamily.Monospace,
)

/**
 * A widget tap.
 *
 * Two writes, in this order: the queue first (the durable record the app will fold in), then the
 * snapshot (so the widget's own redraw shows the new state without waiting for the app). The other
 * order would leave a window in which the widget claims a change the app has no record of.
 */
class ToggleHabitAction : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        val habitId = parameters[habitIdParam] ?: return
        val done = parameters[doneParam] ?: return

        val storage = HabitsRuntime.storage(context)
        val clock = HabitsRuntime.clock(context)
        PendingToggleQueue(storage, HabitsShared.PENDING_TOGGLES_KEY)
            .set(habitId, clock.today(), done, clock.now().toEpochMilli())
        Snapshots.applyToggle(storage, habitId, done, clock.now())

        TodayWidget().updateAll(context)
        TodaySmallWidget().updateAll(context)
    }
}
