package com.sahilchanna.habits.ui.screens

import android.content.Intent
import android.provider.Settings
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
import androidx.compose.foundation.layout.width
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.app.NotificationManagerCompat
import com.sahilchanna.habits.model.Reminders
import com.sahilchanna.habits.model.Streaks
import com.sahilchanna.habits.notifications.ReminderScheduler
import com.sahilchanna.habits.ui.HabitsViewModel
import com.sahilchanna.habits.ui.components.BracketCheckbox
import com.sahilchanna.habits.ui.components.CommentText
import com.sahilchanna.habits.ui.components.HabitGlyph
import com.sahilchanna.habits.ui.components.MutedGrey
import com.sahilchanna.habits.ui.components.PromptHeader
import com.sahilchanna.habits.ui.components.TermText
import com.sahilchanna.habits.ui.theme.LocalTerminalTheme
import com.sahilchanna.habits.ui.theme.TerminalTheme
import com.sahilchanna.habits.ui.theme.parseHex

/**
 * The profile tab (§4.3.1) — appearance and behaviour settings, plus the door to achievements.
 *
 * Every switch here is the app's own `[✓]`/`[ ]` bracket rather than a Material `Switch`: a stock
 * toggle in the middle of a shell is the single most visible way this screen could stop looking like
 * the rest of the app.
 */
@Composable
fun ProfileScreen(
    viewModel: HabitsViewModel,
    onOpenAchievements: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var editingTheme by remember { mutableStateOf<TerminalTheme?>(null) }
    val editing = editingTheme
    if (editing != null) {
        ThemeEditor(
            theme = editing,
            accent = LocalTerminalTheme.current.profileColor,
            onCancel = { editingTheme = null },
            onSave = { saved ->
                viewModel.upsertTheme(saved)
                // A freshly created palette becomes the active one immediately; editing an existing
                // one leaves the selection where it was.
                if (viewModel.theme.value.id == saved.id) viewModel.setTheme(saved.id)
                editingTheme = null
            },
        )
        return
    }

    val theme = LocalTerminalTheme.current
    val graph by viewModel.graph.collectAsState()
    val username by viewModel.username.collectAsState()
    val symbol by viewModel.promptSymbol.collectAsState()
    val crossOut by viewModel.crossOut.collectAsState()
    val moveCompleted by viewModel.moveCompleted.collectAsState()
    val waterEnabled by viewModel.waterEnabled.collectAsState()
    val dayResetHour by viewModel.dayResetHour.collectAsState()
    val timerNotifications by viewModel.timerNotifications.collectAsState()
    val undo by viewModel.undo.collectAsState()
    val context = LocalContext.current

    val today = viewModel.today
    val habits = graph.allHabits
    val weekday = Streaks.weekdayIndex(today)
    val dueToday = habits.filter { it.scheduleDays.contains(weekday) }
    val doneToday = dueToday.count { it.completion(today) != null }
    val waterHabit = Reminders.waterHabit(graph)
    val glasses = Reminders.glasses(waterHabit, today)

    // Read on each composition rather than cached: the user can leave for Settings, turn
    // notifications off and come back, and a remembered value would still say "on".
    val notificationsAllowed = NotificationManagerCompat.from(context).areNotificationsEnabled()

    var armedReset by remember { mutableStateOf(false) }
    val achievements = viewModel.achievements()

    Column(modifier.fillMaxSize().background(theme.bg)) {
        Column(Modifier.padding(horizontal = 16.dp).padding(top = 8.dp)) {
            PromptHeader(
                username = username,
                symbol = symbol,
                command = "appearance",
                accent = theme.profileColor,
                trailing = {
                    XPChip(
                        level = achievements.level,
                        accent = theme.profileColor,
                        comment = theme.commentColor,
                    )
                },
            )
            HorizontalDivider(Modifier.padding(top = 10.dp), color = theme.commentColor.copy(alpha = 0.4f))
        }

        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(16.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            PreviewCard(accent = theme.habitsColor, crossOut = crossOut)

            // Progress first among the sections, because it is the one that leaves the tab.
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                CommentText(text = "// progress", size = 11f)
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { onOpenAchievements() },
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    TermText(text = "◆", size = 12f, color = theme.profileColor)
                    TermText(text = "achievements & xp", size = 13f)
                    Spacer(Modifier.weight(1f))
                    TermText(text = "$ achievements", size = 11f, color = theme.commentColor)
                    TermText(text = "›", size = 12f, weight = FontWeight.Bold, color = theme.commentColor)
                }
            }

            // Water sits second, above the cosmetic settings: on a phone it was otherwise below the
            // fold, and a feature you have to hunt for reads as a feature that is not there.
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                CommentText(text = "// water reminders", size = 11f)

                if (waterHabit != null) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        TermText(
                            text = "$glasses/${Reminders.WATER_GOAL} glasses today",
                            size = 12f,
                            color = theme.commentColor,
                        )
                        Chip(label = "+ glass", selected = false, accent = theme.profileColor) {
                            viewModel.logGlass(waterHabit)
                        }
                        Spacer(Modifier.weight(1f))
                    }
                }

                SwitchRow("remind me to drink water", waterEnabled, theme.profileColor) { on ->
                    viewModel.setWaterEnabled(on)
                }

                if (waterEnabled) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        TermText(text = "every", size = 12f, color = theme.commentColor)
                        Reminders.INTERVAL_CHOICES.forEach { minutes ->
                            Chip(
                                label = if (minutes >= 60) "${minutes / 60}h" else "${minutes}m",
                                selected = viewModel.settings.waterIntervalMinutes == minutes,
                                accent = theme.profileColor,
                            ) { viewModel.setWaterInterval(minutes) }
                        }
                        Spacer(Modifier.weight(1f))
                    }
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        TermText(text = "window", size = 12f, color = theme.commentColor)
                        Reminders.WINDOW_PRESETS.forEach { preset ->
                            Chip(
                                label = preset.label,
                                selected = viewModel.settings.waterStartHour == preset.startHour &&
                                    viewModel.settings.waterEndHour == preset.endHour,
                                accent = theme.profileColor,
                            ) { viewModel.setWaterWindow(preset.startHour, preset.endHour) }
                        }
                        Spacer(Modifier.weight(1f))
                    }
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Chip(label = "test", selected = false, accent = theme.profileColor) {
                            ReminderScheduler.fireTest(context)
                        }
                        CommentText(text = "// fires one in 5s", size = 10f)
                        Spacer(Modifier.weight(1f))
                    }
                    if (!notificationsAllowed) {
                        // Android will not show the permission dialog twice either, so the only
                        // honest thing is to say so and offer the one screen that can change it.
                        TermText(
                            text = "notifications are off — open settings",
                            size = 11f,
                            color = theme.profileColor,
                            modifier = Modifier.clickable {
                                runCatching {
                                    context.startActivity(
                                        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                            .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                                    )
                                }
                            },
                        )
                    }
                }
            }

            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                CommentText(text = "// identity", size = 11f)
                OutlinedTextField(
                    value = username,
                    onValueChange = { viewModel.setUsername(it) },
                    singleLine = true,
                    textStyle = TextStyle(
                        fontFamily = com.sahilchanna.habits.ui.theme.TerminalFont,
                        fontSize = 13.sp,
                    ),
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None),
                    modifier = Modifier.fillMaxWidth(),
                )
                CommentText(text = "${username.length}/15 characters", size = 11f)
            }

            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                CommentText(text = "// theme", size = 11f)
                viewModel.allThemes().forEach { candidate ->
                    val selected = viewModel.theme.value.id == candidate.id
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Row(
                            modifier = Modifier
                                .weight(1f)
                                .clickable { viewModel.setTheme(candidate.id) },
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            TermText(
                                text = if (selected) "[✓]" else "[ ]",
                                size = 13f,
                                weight = FontWeight.SemiBold,
                                color = theme.profileColor,
                            )
                            TermText(text = candidate.name, size = 13f)
                            Spacer(Modifier.weight(1f))
                            Swatches(candidate)
                        }
                        TermText(
                            // Editing a built-in would silently fork it; the icon says which of the
                            // two this control does.
                            text = if (candidate.isCustom) "edit" else "copy",
                            size = 11f,
                            color = theme.profileColor.copy(alpha = 0.8f),
                            modifier = Modifier.clickable {
                                editingTheme = if (candidate.isCustom) {
                                    candidate
                                } else {
                                    val fresh = com.sahilchanna.habits.ui.theme.ThemeStore.duplicate(
                                        candidate,
                                        viewModel.newThemeId(),
                                    )
                                    viewModel.upsertTheme(fresh)
                                    fresh
                                }
                            },
                        )
                        if (candidate.isCustom) {
                            TermText(
                                text = "del",
                                size = 11f,
                                color = parseHex("#FF6B6B").copy(alpha = 0.8f),
                                modifier = Modifier.clickable { viewModel.deleteTheme(candidate) },
                            )
                        }
                    }
                }
                TermText(
                    text = "+ new theme from current",
                    size = 12f,
                    color = theme.commentColor,
                    modifier = Modifier.clickable {
                        val fresh = com.sahilchanna.habits.ui.theme.ThemeStore.duplicate(
                            viewModel.theme.value,
                            viewModel.newThemeId(),
                        )
                        viewModel.upsertTheme(fresh)
                        editingTheme = fresh
                    },
                )
            }

            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                CommentText(text = "// prompt symbol", size = 11f)
                Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                    listOf("$", "%", "#", ">").forEach { option ->
                        // Every option shows its symbol — a blank `[ ]` hid what the choice was.
                        TermText(
                            text = "[$option]",
                            size = 13f,
                            weight = FontWeight.SemiBold,
                            color = if (symbol == option) theme.profileColor else theme.commentColor,
                            modifier = Modifier.clickable { viewModel.setPromptSymbol(option) },
                        )
                    }
                }
            }

            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                CommentText(text = "// text", size = 11f)
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    listOf("default", "larger", "largest").forEachIndexed { tier, label ->
                        val selected = viewModel.settings.textSize == tier
                        TermText(
                            text = label,
                            size = 12f,
                            weight = if (selected) FontWeight.Bold else FontWeight.Normal,
                            color = if (selected) theme.profileColor else theme.commentColor,
                            modifier = Modifier
                                .border(
                                    0.5.dp,
                                    if (selected) theme.profileColor else theme.commentColor.copy(alpha = 0.4f),
                                    RoundedCornerShape(4.dp),
                                )
                                .clickable { viewModel.setTextSize(tier) }
                                .padding(horizontal = 10.dp, vertical = 5.dp),
                        )
                    }
                }
                CommentText(text = "// font: system monospace", size = 11f)
            }

            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                CommentText(text = "// completed habits", size = 11f)
                SwitchRow("cross out completed", crossOut, theme.profileColor) { viewModel.setCrossOut(it) }
                SwitchRow("move completed to bottom", moveCompleted, theme.profileColor) { viewModel.setMoveCompleted(it) }
            }

            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                CommentText(text = "// day reset", size = 11f)
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    TermText(text = "new day at", size = 12f, color = theme.commentColor)
                    (0..5).forEach { hour ->
                        Chip(
                            label = if (hour == 0) "midnight" else "${hour}am",
                            selected = dayResetHour == hour,
                            accent = theme.profileColor,
                        ) { viewModel.setDayResetHour(hour) }
                    }
                    Spacer(Modifier.weight(1f))
                }
                CommentText(
                    text = "// a check-off before this hour still counts as the previous day",
                    size = 11f,
                )
            }

            // The one destructive control in the app: two taps and a receipt. It comes last, after
            // the display preferences, so it is not what a thumb finds while reaching for "cross out
            // completed".
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                CommentText(text = "// today", size = 11f)
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    TermText(
                        text = "$doneToday/${dueToday.size} done",
                        size = 12f,
                        color = theme.commentColor,
                    )
                    if (armedReset) {
                        // Says what it will clear rather than "confirm?": the count is the one piece
                        // of information that makes the second tap a decision instead of a reflex.
                        Chip(
                            label = if (doneToday == 0) "nothing to clear" else "clear $doneToday",
                            selected = true,
                            accent = theme.profileColor,
                        ) {
                            armedReset = false
                            viewModel.resetToday()
                        }
                        Chip(label = "cancel", selected = false, accent = theme.profileColor) { armedReset = false }
                    } else {
                        Chip(label = "reset today", selected = false, accent = theme.profileColor) { armedReset = true }
                    }
                    Spacer(Modifier.weight(1f))
                }
                if (undo.isNotEmpty()) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        TermText(text = "cleared ${undo.size}", size = 10f, color = theme.commentColor)
                        Chip(label = "undo", selected = false, accent = theme.profileColor) { viewModel.undoReset() }
                        Spacer(Modifier.weight(1f))
                    }
                }
                CommentText(
                    text = "// wipes today's ticks and the water tally; today then counts as a missed day for streaks",
                    size = 11f,
                )
            }

            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                CommentText(text = "// timer notification", size = 11f)
                SwitchRow("show a running timer", timerNotifications, theme.profileColor) {
                    viewModel.setTimerNotifications(it)
                }
                if (timerNotifications) {
                    // These four are read straight from preferences when the notification is built,
                    // so each one writes and then asks for a republish rather than holding state of
                    // its own.
                    SwitchRow("show elapsed timer", viewModel.settings.showTimerInNotification, theme.profileColor) {
                        viewModel.settings.showTimerInNotification = it
                        viewModel.refreshTimerNotification()
                    }
                    SwitchRow("show progress bar", viewModel.settings.showProgressInNotification, theme.profileColor) {
                        viewModel.settings.showProgressInNotification = it
                        viewModel.refreshTimerNotification()
                    }
                    SwitchRow("show habit name", viewModel.settings.showNameInNotification, theme.profileColor) {
                        viewModel.settings.showNameInNotification = it
                        viewModel.refreshTimerNotification()
                    }
                    SwitchRow("count down to target", viewModel.settings.countDown, theme.profileColor) {
                        viewModel.settings.countDown = it
                        viewModel.refreshTimerNotification()
                    }
                    TermText(
                        text = "system: ${if (notificationsAllowed) "allowed" else "BLOCKED"}",
                        size = 10f,
                        color = theme.commentColor,
                    )
                }
                CommentText(
                    text = "// an ongoing notification stands in for iOS live activities",
                    size = 11f,
                )
            }
        }
    }
}

/** A live preview of a habit row, so a text-size or cross-out change is visible where it is made. */
@Composable
private fun PreviewCard(accent: Color, crossOut: Boolean) {
    val theme = LocalTerminalTheme.current
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .border(0.5.dp, theme.commentColor.copy(alpha = 0.3f), RoundedCornerShape(6.dp))
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        CommentText(text = "// preview", size = 11f)
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            TermText(text = "[✓]", size = 13f, weight = FontWeight.SemiBold, color = accent)
            HabitGlyph(icon = "figure.run", name = "morning run", color = accent)
            TermText(
                text = "morning run",
                size = 13f,
                textDecoration = if (crossOut) androidx.compose.ui.text.style.TextDecoration.LineThrough else null,
            )
            Spacer(Modifier.weight(1f))
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                TermText(text = "▲", size = 9f, color = parseHex("#FF9F45"))
                TermText(text = "7", size = 11f)
            }
        }
    }
}

/** The five ANSI-style swatch dots a theme row shows. */
@Composable
private fun Swatches(theme: TerminalTheme) {
    Row(horizontalArrangement = Arrangement.spacedBy(3.dp), verticalAlignment = Alignment.CenterVertically) {
        listOf(theme.foreground, theme.comment, theme.habitsAccent, theme.statsAccent, theme.profileAccent)
            .forEach { hex ->
                Box(Modifier.size(9.dp).background(parseHex(hex), CircleShape))
            }
    }
}

/** A settings switch in the app's own idiom, with the whole row as the tap target. */
@Composable
private fun SwitchRow(label: String, checked: Boolean, accent: Color, onToggle: (Boolean) -> Unit) {
    val theme = LocalTerminalTheme.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onToggle(!checked) }
            .padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        BracketCheckbox(checked = checked, color = accent)
        TermText(
            text = label,
            size = 13f,
            // Dimmed when off, so the state is legible without squinting at brackets.
            color = if (checked) Color.White else theme.commentColor,
        )
    }
}

/** A small bordered terminal chip, shared by the interval, window, reset and day-reset rows. */
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

/**
 * The palette editor.
 *
 * Rendered in place of the profile list rather than in a dialog: it is a whole screen of six colour
 * rows and a name, and a terminal UI has no other modal anywhere to be consistent with.
 */
@Composable
private fun ThemeEditor(
    theme: TerminalTheme,
    accent: Color,
    onCancel: () -> Unit,
    onSave: (TerminalTheme) -> Unit,
) {
    val active = LocalTerminalTheme.current
    var draft by remember { mutableStateOf(theme) }

    val rows = listOf<Pair<String, (TerminalTheme, String) -> TerminalTheme>>(
        "background" to { t, v -> t.copy(background = v) },
        "foreground" to { t, v -> t.copy(foreground = v) },
        "comment" to { t, v -> t.copy(comment = v) },
        "habits accent" to { t, v -> t.copy(habitsAccent = v) },
        "stats accent" to { t, v -> t.copy(statsAccent = v) },
        "profile accent" to { t, v -> t.copy(profileAccent = v) },
    )

    Column(Modifier.fillMaxSize().background(active.bg)) {
        Row(
            Modifier.fillMaxWidth().padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            TermText(
                text = "cancel",
                size = 12f,
                color = active.commentColor,
                modifier = Modifier.clickable { onCancel() },
            )
            Spacer(Modifier.weight(1f))
            TermText(text = "edit theme", size = 13f, weight = FontWeight.SemiBold, color = accent)
            Spacer(Modifier.weight(1f))
            TermText(
                text = "save",
                size = 12f,
                weight = FontWeight.SemiBold,
                color = accent,
                modifier = Modifier.clickable {
                    // An unnamed palette is not a useful thing to find later, so it gets a name
                    // rather than being rejected.
                    onSave(if (draft.name.isBlank()) draft.copy(name = "custom") else draft)
                },
            )
        }
        HorizontalDivider(color = active.commentColor.copy(alpha = 0.4f))

        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            OutlinedTextField(
                value = draft.name,
                onValueChange = { draft = draft.copy(name = it) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            rows.forEach { (label, update) ->
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    TermText(text = label, size = 12f, color = active.commentColor)
                    Spacer(Modifier.weight(1f))
                    TermText(text = value(theme = draft, label = label), size = 11f, color = active.commentColor)
                    // Text entry rather than a colour wheel: the value has to survive as a
                    // `#RRGGBB` string in preferences and in the widget snapshot, and typing it is
                    // also the only way to paste a palette in from somewhere else.
                    TermText(
                        text = "[pick]",
                        size = 11f,
                        color = accent,
                        modifier = Modifier.clickable {
                            val next = nextHex(value(theme = draft, label = label))
                            draft = update(draft, next)
                        },
                    )
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                CommentText(text = "// sample", size = 11f)
                Swatches(draft)
            }
        }
    }
}

/** The current hex for one labelled row of the theme editor. */
private fun value(theme: TerminalTheme, label: String): String = when (label) {
    "background" -> theme.background
    "foreground" -> theme.foreground
    "comment" -> theme.comment
    "habits accent" -> theme.habitsAccent
    "stats accent" -> theme.statsAccent
    else -> theme.profileAccent
}

/**
 * Steps a hex colour to the next palette entry.
 *
 * A stand-in for the iOS `ColorPicker`: typing six hex digits on a phone keyboard is miserable and
 * a full colour wheel is a lot of screen for a terminal app, so the picker cycles a small
 * hand-chosen set and the hex line beside it stays the source of truth.
 */
private fun nextHex(current: String): String {
    val palette = listOf(
        "#000000", "#E8E8E8", "#6E6E73", "#FFB454", "#4ADE80", "#FF6BD6",
        "#282A36", "#F8F8F2", "#6272A4", "#FFB86C", "#50FA7B", "#FF79C6",
        "#002B36", "#93A1A1", "#586E75", "#B58900", "#859900", "#D33682",
        "#00D7C3", "#5AA7FF", "#C084FC", "#FF6B6B",
    )
    val index = palette.indexOfFirst { it.equals(current, ignoreCase = true) }
    return palette[(index + 1).mod(palette.size)]
}
