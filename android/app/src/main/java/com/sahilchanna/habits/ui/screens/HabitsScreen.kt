package com.sahilchanna.habits.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import com.sahilchanna.habits.data.Habit
import com.sahilchanna.habits.model.Elapsed
import com.sahilchanna.habits.model.HabitType
import com.sahilchanna.habits.model.Reminders
import com.sahilchanna.habits.model.Streaks
import com.sahilchanna.habits.ui.HabitsViewModel
import com.sahilchanna.habits.ui.components.BracketCheckbox
import com.sahilchanna.habits.ui.components.CommentText
import com.sahilchanna.habits.ui.components.HabitGlyph
import com.sahilchanna.habits.ui.components.MutedGrey
import com.sahilchanna.habits.ui.components.PromptHeader
import com.sahilchanna.habits.ui.components.TermText
import com.sahilchanna.habits.ui.components.WeekStrip
import com.sahilchanna.habits.ui.theme.LocalTerminalTheme
import com.sahilchanna.habits.ui.theme.parseHex
import java.time.LocalDate

/**
 * The habits tab (§4.1) — the home screen.
 *
 * The header is a rotating tagline picked by the day of the year, the week strip selects the day
 * the rest of the screen reads, and the routines below are collapsible groups of habit rows.
 */
@Composable
fun HabitsScreen(
    viewModel: HabitsViewModel,
    onAddHabit: () -> Unit,
    onEditHabit: (Habit) -> Unit,
    modifier: Modifier = Modifier,
) {
    val theme = LocalTerminalTheme.current
    val graph by viewModel.graph.collectAsState()
    val selectedDay by viewModel.selectedDay.collectAsState()
    val username by viewModel.username.collectAsState()
    val symbol by viewModel.promptSymbol.collectAsState()
    val crossOut by viewModel.crossOut.collectAsState()
    val moveCompleted by viewModel.moveCompleted.collectAsState()
    val undo by viewModel.undo.collectAsState()
    // Collected purely to recompose the live timer text once a second.
    val tick by viewModel.ticker.collectAsState()

    val today = viewModel.today
    val unfiled = graph.unfiledHabits

    val taglines = listOf(
        "// discipline is a compile-time guarantee",
        "// ship small, ship daily",
        "// zero warnings, one habit at a time",
        "// consistency > intensity",
        "// refactor yourself, one commit a day",
    )

    // The undo bar is an overlay rather than a row in the column: it is offered for a few seconds
    // and must not shove the list it is talking about up and down while it is there.
    Box(modifier = modifier.fillMaxSize().background(theme.bg)) {
        Column(Modifier.fillMaxSize()) {
            Column(Modifier.padding(horizontal = 16.dp).padding(top = 8.dp)) {
            PromptHeader(
                username = username,
                symbol = symbol,
                command = "daily",
                accent = theme.habitsColor,
            )
            HorizontalDivider(Modifier.padding(top = 10.dp), color = theme.commentColor.copy(alpha = 0.4f))
        }

        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            // One tagline a day rather than one per render: a line that changes every time the
            // screen is opened is decoration, not a voice.
            CommentText(text = taglines[(selectedDay.dayOfYear % taglines.size)])

            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                TermText(text = "▤", size = 12f, color = theme.commentColor)
                TermText(text = formatLongDate(selectedDay), size = 13f)
            }

            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                TermText(text = "▲", size = 12f, color = parseHex("#FF9F45"))
                TermText(text = viewModel.todayStreak().toString(), size = 13f, weight = FontWeight.SemiBold)
                CommentText(text = "*")
                TermText(text = "⛨", size = 12f, color = theme.commentColor)
                TermText(text = "0", size = 13f, weight = FontWeight.SemiBold)
            }

            WeekStrip(
                week = viewModel.clock.weekDates(selectedDay),
                selected = selectedDay,
                today = today,
                habits = graph.allHabits,
                onSelect = viewModel::selectDay,
            )

            if (graph.routines.isEmpty() && unfiled.isEmpty()) {
                CommentText(text = "// no routines yet — tap + add habit")
            } else {
                graph.routines.forEach { routine ->
                    RoutineSection(
                        routine = routine,
                        selectedDay = selectedDay,
                        today = today,
                        moveCompleted = moveCompleted,
                        crossOut = crossOut,
                        tick = tick,
                        viewModel = viewModel,
                        onEditHabit = onEditHabit,
                    )
                }
                if (unfiled.isNotEmpty()) {
                    UnfiledSection(
                        habits = unfiled,
                        selectedDay = selectedDay,
                        today = today,
                        moveCompleted = moveCompleted,
                        crossOut = crossOut,
                        tick = tick,
                        viewModel = viewModel,
                        onEditHabit = onEditHabit,
                    )
                }
            }

            TermText(
                text = "+ add habit",
                size = 13f,
                color = theme.commentColor,
                modifier = Modifier
                    .padding(top = 4.dp)
                    .clickable { onAddHabit() },
            )
        }

        // The undo bar. Only present while a reset is still undoable, so it never becomes
        // furniture on the screen.
        if (undo.isNotEmpty()) {
            Row(
                modifier = Modifier
                    .align(Alignment.CenterHorizontally)
                    .fillMaxWidth()
                    .background(theme.commentColor.copy(alpha = 0.15f))
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                CommentText(text = "// cleared ${undo.size} for today")
                Spacer(Modifier.weight(1f))
                TermText(
                    text = "[undo]",
                    size = 12f,
                    weight = FontWeight.SemiBold,
                    color = theme.habitsColor,
                    modifier = Modifier.clickable { viewModel.undoReset() },
                )
                Spacer(Modifier.width(12.dp))
                TermText(
                    text = "[x]",
                    size = 12f,
                    color = MutedGrey,
                    modifier = Modifier.clickable { viewModel.dismissUndo() },
                )
            }
        }
        }
    }
}

@Composable
private fun RoutineSection(
    routine: com.sahilchanna.habits.data.Routine,
    selectedDay: LocalDate,
    today: LocalDate,
    moveCompleted: Boolean,
    crossOut: Boolean,
    tick: Long,
    viewModel: HabitsViewModel,
    onEditHabit: (Habit) -> Unit,
) {
    val theme = LocalTerminalTheme.current
    var expanded by remember { mutableStateOf(true) }

    val forDay = routine.habits.filter { it.scheduleDays.contains(Streaks.weekdayIndex(selectedDay)) }
    val sorted = sortedHabits(forDay, selectedDay, moveCompleted)
    val done = forDay.count { it.completion(selectedDay) != null }

    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth().clickable { expanded = !expanded },
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            TermText(text = if (expanded) "▾" else "▸", size = 11f, color = MutedGrey)
            HabitGlyph(icon = routine.icon, name = routine.name, color = theme.habitsColor)
            TermText(text = routine.name, size = 14f, weight = FontWeight.SemiBold)
            CommentText(text = routine.subtitle)
            Spacer(Modifier.weight(1f))
            Tally(done = done, total = forDay.size, accent = theme.habitsColor)
        }
        if (expanded) {
            sorted.forEach { habit ->
                HabitRow(
                    habit = habit,
                    day = selectedDay,
                    today = today,
                    crossOut = crossOut,
                    tick = tick,
                    viewModel = viewModel,
                    onEditHabit = onEditHabit,
                )
            }
        }
    }
}

@Composable
private fun UnfiledSection(
    habits: List<Habit>,
    selectedDay: LocalDate,
    today: LocalDate,
    moveCompleted: Boolean,
    crossOut: Boolean,
    tick: Long,
    viewModel: HabitsViewModel,
    onEditHabit: (Habit) -> Unit,
) {
    val theme = LocalTerminalTheme.current
    var expanded by remember { mutableStateOf(true) }

    val forDay = habits.filter { it.scheduleDays.contains(Streaks.weekdayIndex(selectedDay)) }
    val sorted = sortedHabits(forDay, selectedDay, moveCompleted)
    val done = forDay.count { it.completion(selectedDay) != null }

    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth().clickable { expanded = !expanded },
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            TermText(text = if (expanded) "▾" else "▸", size = 11f, color = MutedGrey)
            HabitGlyph(icon = "tray", name = "unfiled", color = theme.habitsColor)
            TermText(text = "unfiled", size = 14f, weight = FontWeight.SemiBold)
            CommentText(text = "// no routine")
            Spacer(Modifier.weight(1f))
            Tally(done = done, total = forDay.size, accent = theme.habitsColor)
        }
        if (expanded) {
            sorted.forEach { habit ->
                HabitRow(
                    habit = habit,
                    day = selectedDay,
                    today = today,
                    crossOut = crossOut,
                    tick = tick,
                    viewModel = viewModel,
                    onEditHabit = onEditHabit,
                )
            }
        }
    }
}

/** `[3/5]`, lit up once everything scheduled for the day is done. */
@Composable
private fun Tally(done: Int, total: Int, accent: androidx.compose.ui.graphics.Color) {
    TermText(
        text = "[$done/$total]",
        size = 11f,
        weight = FontWeight.SemiBold,
        color = if (done == total && total > 0) accent else MutedGrey,
    )
}

/**
 * A habit row.
 *
 * "Move completed to bottom" is applied by the caller, which is why the sort lives in one helper
 * rather than in each section — the two sections have to order identically or a habit appears to
 * jump when it is filed or unfiled.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun HabitRow(
    habit: Habit,
    day: LocalDate,
    today: LocalDate,
    crossOut: Boolean,
    tick: Long,
    viewModel: HabitsViewModel,
    onEditHabit: (Habit) -> Unit,
) {
    val theme = LocalTerminalTheme.current
    val color = habit.color.let { parseHex(it.hex) }
    val completion = habit.completion(day)
    val isToday = day == today
    val streak = Streaks.habitStreak(habit, today)
    val isWater = Reminders.isWaterHabit(habit)
    var menuOpen by remember { mutableStateOf(false) }

    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(
            modifier = Modifier
                .weight(1f)
                .combinedClickable(
                    onClick = { viewModel.toggle(habit) },
                    onLongClick = { menuOpen = true },
                ),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Box(
                // A past day that was never done is not waiting for a tick: faded rather than
                // tappable, so the row explains itself instead of swallowing taps.
                modifier = Modifier
                    .clickable(enabled = isToday || completion != null) { viewModel.toggle(habit) }
                    .then(if (!isToday && completion == null) Modifier.alpha(0.4f) else Modifier),
            ) {
                BracketCheckbox(checked = completion != null, color = color)
            }

            HabitGlyph(icon = habit.icon, name = habit.name, color = color)

            Column {
                TermText(
                    text = habit.name,
                    size = 13f,
                    textDecoration = if (completion != null && crossOut) TextDecoration.LineThrough else null,
                )
                if (habit.comment.isNotEmpty()) CommentText(text = habit.comment)
            }

            Spacer(Modifier.weight(1f))

            if (streak > 0) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    TermText(text = "▲", size = 9f, color = parseHex("#FF9F45"))
                    TermText(text = streak.toString(), size = 11f)
                }
            }

            // A reminder is a setting, not a state, so it shows whether or not the day is done —
            // and as a time, because a bell alone leaves "when?" to be found by opening the habit.
            habit.reminderMinutesFromMidnight?.let { minutes ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    TermText(text = "◔", size = 9f, color = theme.commentColor)
                    TermText(text = viewModel.clock.formatClock(minutes), size = 10f, color = theme.commentColor)
                }
            }

            // Water is measured in glasses rather than a tick, so the row reports the tally beside
            // the streak — the `[+]` that changes it is its own button, below.
            if (isWater) {
                TermText(
                    text = "${(completion?.value ?: 0.0).toInt()}/${Reminders.WATER_GOAL}",
                    size = 10f,
                    color = theme.commentColor,
                )
            }

            StatusMeta(habit = habit, completion = completion, isToday = isToday, tick = tick, color = color)
        }

        if (isWater) {
            TermText(
                text = "[+]",
                size = 12f,
                weight = FontWeight.SemiBold,
                color = color,
                modifier = Modifier
                    .clickable { viewModel.logGlass(habit) }
                    .padding(horizontal = 2.dp),
            )
        }

        DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
            if (isWater) {
                DropdownMenuItem(
                    text = { TermText(text = "log a glass", size = 12f) },
                    onClick = { menuOpen = false; viewModel.logGlass(habit) },
                )
            }
            if (habit.startedAt != null) {
                DropdownMenuItem(
                    text = { TermText(text = if (habit.isPaused) "resume timer" else "pause timer", size = 12f) },
                    onClick = { menuOpen = false; viewModel.togglePause(habit) },
                )
            }
            DropdownMenuItem(
                text = { TermText(text = "edit habit", size = 12f) },
                onClick = { menuOpen = false; onEditHabit(habit) },
            )
            DropdownMenuItem(
                text = { TermText(text = "delete habit", size = 12f, color = parseHex("#FF6B6B")) },
                onClick = { menuOpen = false; viewModel.deleteHabit(habit) },
            )
        }
    }
}

/**
 * What sits at the right of a row: when it was done, or a live timer.
 *
 * The timer only appears on today's row. A running timer shown against a past day would claim the
 * seconds were logged there, when they are still accumulating against today.
 */
@Composable
private fun StatusMeta(
    habit: Habit,
    completion: com.sahilchanna.habits.data.Completion?,
    isToday: Boolean,
    tick: Long,
    color: androidx.compose.ui.graphics.Color,
) {
    val theme = LocalTerminalTheme.current
    if (completion != null) {
        if (isToday) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                TermText(text = "◷", size = 9f, color = theme.commentColor)
                TermText(
                    text = formatShortTime(completion.completedAt),
                    size = 10f,
                    color = theme.commentColor,
                )
            }
        } else {
            TermText(text = "✓", size = 11f, color = color.copy(alpha = 0.6f))
        }
        return
    }
    if (habit.type == HabitType.TIMED && habit.startedAt != null && isToday) {
        // Reading `tick` is what makes this recompose once a second — the value itself is unused
        // here, because the elapsed time is computed from the habit's own start instant.
        @Suppress("UNUSED_EXPRESSION") tick
        val paused = habit.isPaused
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
            TermText(text = if (paused) "‖" else "⏱", size = 9f, color = if (paused) theme.commentColor else theme.habitsColor)
            TermText(
                text = habit.formattedElapsed(java.time.Instant.now()),
                size = 10f,
                weight = FontWeight.SemiBold,
            )
            CommentText(text = "/")
            CommentText(text = Elapsed.targetLabel(habit.targetSeconds).replace("// ", ""), size = 10f)
            if (paused) CommentText(text = "paused", size = 10f)
        }
    }
}

/** The completed-at clock time, in the device's own zone. */
private fun formatShortTime(instant: java.time.Instant): String {
    val t = instant.atZone(java.time.ZoneId.systemDefault()).toLocalTime()
    return "%02d:%02d".format(t.hour, t.minute)
}

/** `Monday, 9 March 2026` — the long form the header prints. */
private fun formatLongDate(day: LocalDate): String =
    day.dayOfWeek.name.lowercase().replaceFirstChar { it.uppercase() } +
        ", ${day.dayOfMonth} " +
        day.month.name.lowercase().replaceFirstChar { it.uppercase() } +
        " ${day.year}"

/** The one ordering rule both sections share. */
private fun sortedHabits(habits: List<Habit>, day: LocalDate, moveCompleted: Boolean): List<Habit> {
    val byIndex = habits.sortedBy { it.sortIndex }
    if (!moveCompleted) return byIndex
    // A stable partition rather than a comparator on a boolean: `sortedBy` on the done flag would
    // reorder the completed rows amongst themselves, so a row would jump twice on one tap.
    return byIndex.filter { it.completion(day) == null } + byIndex.filter { it.completion(day) != null }
}
