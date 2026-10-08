package com.sahilchanna.habits.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.OutlinedTextField
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.sahilchanna.habits.data.Habit
import com.sahilchanna.habits.model.HabitColor
import com.sahilchanna.habits.model.HabitType
import com.sahilchanna.habits.ui.HabitsViewModel
import com.sahilchanna.habits.ui.components.CommentText
import com.sahilchanna.habits.ui.components.HabitGlyph
import com.sahilchanna.habits.ui.components.IconChoices
import com.sahilchanna.habits.ui.components.PromptHeader
import com.sahilchanna.habits.ui.components.TermSegmentBar
import com.sahilchanna.habits.ui.components.TermText
import com.sahilchanna.habits.ui.theme.LocalTerminalTheme
import com.sahilchanna.habits.ui.theme.TerminalFont
import com.sahilchanna.habits.ui.theme.parseHex

/**
 * Create or edit one habit: name, icon, colour, type, schedule, routine and reminder.
 *
 * Pass an existing habit to edit it in place. The screen is a plain scrolling form rather than a
 * Material scaffold — there is no `TopAppBar` anywhere in this app, and the save/cancel controls are
 * terminal text like every other action.
 */
@Composable
fun AddHabitScreen(
    viewModel: HabitsViewModel,
    existing: Habit?,
    onDone: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val theme = LocalTerminalTheme.current
    val graph by viewModel.graph.collectAsState()
    val username by viewModel.username.collectAsState()
    val symbol by viewModel.promptSymbol.collectAsState()

    // Seeded once from the habit being edited, then owned by the form. Reading it out of the store
    // on every recomposition would fight the fields the user is typing into.
    var name by remember { mutableStateOf(existing?.name.orEmpty()) }
    var icon by remember { mutableStateOf(existing?.icon ?: "circle") }
    var color by remember { mutableStateOf(existing?.color ?: HabitColor.DEFAULT) }
    var type by remember { mutableStateOf(existing?.type ?: HabitType.CHECKBOX) }
    var targetMinutes by remember {
        mutableStateOf(if (existing != null && existing.targetSeconds > 0) (existing.targetSeconds / 60).toInt() else 10)
    }
    // The stored comment carries its own `// ` prefix; the field edits the text without it.
    var comment by remember { mutableStateOf(existing?.comment?.removePrefix("// ").orEmpty()) }
    var routineId by remember { mutableStateOf(existing?.routineId ?: graph.routines.firstOrNull()?.id) }
    var scheduleDays by remember { mutableStateOf(existing?.scheduleDays ?: setOf(1, 2, 3, 4, 5, 6, 7)) }
    var reminderOn by remember { mutableStateOf(existing?.reminderMinutesFromMidnight != null) }
    var reminderMinutes by remember { mutableStateOf(existing?.reminderMinutesFromMidnight ?: (8 * 60)) }
    var armedDelete by remember { mutableStateOf(false) }

    val accent = parseHex(color.hex)

    Column(modifier.fillMaxSize().background(theme.bg)) {
        Column(Modifier.padding(horizontal = 16.dp).padding(top = 8.dp)) {
            PromptHeader(
                username = username,
                symbol = symbol,
                command = if (existing == null) "new habit" else "edit habit",
                accent = theme.habitsColor,
            )
            HorizontalDivider(Modifier.padding(top = 10.dp), color = theme.commentColor.copy(alpha = 0.4f))
        }

        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(16.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            Section("name") {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    singleLine = true,
                    textStyle = TextStyle(fontFamily = TerminalFont, fontSize = 14.sp),
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None),
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            Section("icon") {
                IconChoices.chunked(6).forEach { row ->
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        row.forEach { candidate ->
                            val selected = icon == candidate
                            Box(
                                modifier = Modifier
                                    .weight(1f)
                                    .background(
                                        if (selected) accent.copy(alpha = 0.15f) else Color.Transparent,
                                        RoundedCornerShape(5.dp),
                                    )
                                    .clickable { icon = candidate }
                                    .padding(vertical = 8.dp),
                                contentAlignment = Alignment.Center,
                            ) {
                                HabitGlyph(
                                    icon = candidate,
                                    name = candidate,
                                    color = if (selected) accent else theme.commentColor,
                                )
                            }
                        }
                        // The last row can be short; empty weights keep its cells the same width as
                        // every other row's rather than letting them stretch.
                        repeat(6 - row.size) { Spacer(Modifier.weight(1f)) }
                    }
                }
            }

            Section("color") {
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    HabitColor.entries.forEach { candidate ->
                        val selected = color == candidate
                        Box(
                            modifier = Modifier
                                .size(26.dp)
                                .background(parseHex(candidate.hex), CircleShape)
                                .border(if (selected) 1.5.dp else 0.dp, Color.White, CircleShape)
                                .clickable { color = candidate },
                        )
                    }
                }
            }

            Section("type") {
                TermSegmentBar(
                    options = HabitType.entries.map { it.raw to it.label },
                    selection = type.raw,
                    accent = theme.habitsColor,
                    onSelect = { type = HabitType.from(it) },
                )
                if (type == HabitType.TIMED) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        TermText(text = "target", size = 12f, color = theme.commentColor)
                        Chip("−5", false, accent) { targetMinutes = (targetMinutes - 5).coerceAtLeast(1) }
                        TermText(text = "$targetMinutes min", size = 13f, weight = FontWeight.SemiBold)
                        Chip("+5", false, accent) { targetMinutes = (targetMinutes + 5).coerceAtMost(480) }
                    }
                }
            }

            Section("schedule") {
                val letters = listOf("M", "T", "W", "T", "F", "S", "S")
                // Monday-first, matching the week strip and the heatmap.
                val weekdays = listOf(2, 3, 4, 5, 6, 7, 1)
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    weekdays.forEachIndexed { index, weekday ->
                        val selected = scheduleDays.contains(weekday)
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .background(
                                    if (selected) accent.copy(alpha = 0.18f) else Color.Transparent,
                                    RoundedCornerShape(4.dp),
                                )
                                .border(
                                    0.5.dp,
                                    if (selected) accent else theme.commentColor.copy(alpha = 0.4f),
                                    RoundedCornerShape(4.dp),
                                )
                                .clickable {
                                    scheduleDays = if (selected) scheduleDays - weekday else scheduleDays + weekday
                                }
                                .padding(vertical = 6.dp),
                            contentAlignment = Alignment.Center,
                        ) {
                            TermText(
                                text = letters[index],
                                size = 11f,
                                weight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
                                color = if (selected) accent else theme.commentColor,
                            )
                        }
                    }
                }
                CommentText(
                    text = if (scheduleDays.isEmpty()) "// unscheduled — this habit will never appear" else "// ${scheduleSummary(scheduleDays)}",
                    size = 11f,
                )
            }

            Section("comment (optional)") {
                OutlinedTextField(
                    value = comment,
                    onValueChange = { comment = it },
                    singleLine = true,
                    placeholder = { TermText(text = "// e.g. after waking up", size = 13f, color = theme.commentColor) },
                    textStyle = TextStyle(fontFamily = TerminalFont, fontSize = 14.sp),
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None),
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            Section("routine") {
                val routines = graph.routines
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Chip("none", routineId == null, accent) { routineId = null }
                    routines.forEach { routine ->
                        Chip(routine.name, routineId == routine.id, accent) { routineId = routine.id }
                    }
                }
            }

            Section("reminder") {
                Row(
                    modifier = Modifier.fillMaxWidth().clickable { reminderOn = !reminderOn },
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    TermText(
                        text = if (reminderOn) "[✓]" else "[ ]",
                        size = 13f,
                        weight = FontWeight.SemiBold,
                        color = if (reminderOn) accent else theme.commentColor,
                    )
                    TermText(text = "remind me", size = 13f)
                    Spacer(Modifier.weight(1f))
                    if (reminderOn) {
                        TermText(
                            text = "%02d:%02d".format(reminderMinutes / 60, reminderMinutes % 60),
                            size = 13f,
                            weight = FontWeight.SemiBold,
                        )
                    }
                }
                if (reminderOn) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        listOf(6, 7, 8, 9, 12, 18, 20, 21, 22).forEach { hour ->
                            val selected = reminderMinutes / 60 == hour
                            Chip("%02d".format(hour), selected, accent) {
                                reminderMinutes = hour * 60 + reminderMinutes % 60
                            }
                        }
                    }
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        listOf(0, 15, 30, 45).forEach { minute ->
                            val selected = reminderMinutes % 60 == minute
                            Chip(":%02d".format(minute), selected, accent) {
                                reminderMinutes = (reminderMinutes / 60) * 60 + minute
                            }
                        }
                    }
                    CommentText(text = "// fires on the days this habit is scheduled", size = 11f)
                }
            }

            if (existing != null) {
                Section("danger") {
                    if (armedDelete) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Chip("delete ${existing.name}", true, parseHex("#FF6B6B")) {
                                viewModel.deleteHabit(existing)
                                onDone()
                            }
                            Chip("cancel", false, accent) { armedDelete = false }
                        }
                    } else {
                        Chip("delete habit", false, parseHex("#FF6B6B")) { armedDelete = true }
                    }
                }
            }

            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                TermText(
                    text = "[cancel]",
                    size = 13f,
                    color = theme.commentColor,
                    modifier = Modifier.clickable { onDone() },
                )
                TermText(
                    text = if (existing == null) "[add]" else "[save]",
                    size = 13f,
                    weight = FontWeight.SemiBold,
                    color = accent,
                    modifier = Modifier.clickable {
                        save(viewModel, existing, name, icon, color, type, targetMinutes, comment, routineId, scheduleDays, reminderOn, reminderMinutes)
                        onDone()
                    },
                )
            }
        }
    }
}

/**
 * Writes the form back to the store.
 *
 * The mutations iOS performs on save are all here, including the one that is easy to miss: demoting
 * a timed habit to a check-off ends any running timer, because a timer with nothing to count against
 * would keep running in the notification with no way to stop it from this screen.
 */
private fun save(
    viewModel: HabitsViewModel,
    existing: Habit?,
    name: String,
    icon: String,
    color: HabitColor,
    type: HabitType,
    targetMinutes: Int,
    comment: String,
    routineId: String?,
    scheduleDays: Set<Int>,
    reminderOn: Boolean,
    reminderMinutes: Int,
) {
    val habit = existing ?: Habit()
    habit.name = name.ifBlank { "untitled" }
    habit.icon = icon
    habit.color = color
    if (habit.type != type && type == HabitType.CHECKBOX) habit.clearTimer()
    habit.type = type
    if (type == HabitType.TIMED) habit.targetSeconds = targetMinutes.toLong() * 60
    habit.comment = if (comment.isBlank()) "" else "// ${comment.removePrefix("// ")}"
    habit.scheduleDays = if (scheduleDays.isEmpty()) setOf(1, 2, 3, 4, 5, 6, 7) else scheduleDays
    habit.reminderMinutesFromMidnight = if (reminderOn) reminderMinutes else null
    habit.routineId = routineId
    if (existing == null) {
        // A brand-new habit's creation instant is its "first tracked day", so an epoch default here
        // would make every stats denominator wrong from the moment it is added. Taken from the app's
        // clock rather than `Instant.now()` so it agrees with the day-reset rule everywhere else.
        habit.createdAt = viewModel.clock.now()
        habit.sortIndex = viewModel.graph.value.allHabits.size
    }
    viewModel.saveHabit(habit)
}

/** `daily` / `weekdays` / `weekends` / `M·W·F`, the same labels the stats summary prints. */
private fun scheduleSummary(days: Set<Int>): String = when {
    days.size == 7 -> "daily"
    days == setOf(2, 3, 4, 5, 6) -> "weekdays"
    days == setOf(1, 7) -> "weekends"
    else -> {
        val names = mapOf(2 to "M", 3 to "T", 4 to "W", 5 to "T", 6 to "F", 7 to "S", 1 to "S")
        listOf(2, 3, 4, 5, 6, 7, 1).filter { days.contains(it) }.mapNotNull { names[it] }.joinToString("·")
    }
}

@Composable
private fun Section(label: String, content: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        CommentText(text = "// $label", size = 11f)
        content()
    }
}

@Composable
private fun Chip(label: String, selected: Boolean, accent: Color, onClick: () -> Unit) {
    val theme = LocalTerminalTheme.current
    TermText(
        text = label,
        size = 12f,
        weight = if (selected) FontWeight.Bold else FontWeight.Normal,
        color = if (selected) accent else theme.commentColor,
        modifier = Modifier
            .border(
                0.5.dp,
                if (selected) accent else theme.commentColor.copy(alpha = 0.4f),
                RoundedCornerShape(4.dp),
            )
            .clickable { onClick() }
            .padding(horizontal = 8.dp, vertical = 4.dp),
    )
}
