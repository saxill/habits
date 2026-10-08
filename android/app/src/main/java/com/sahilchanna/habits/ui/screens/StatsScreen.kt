package com.sahilchanna.habits.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.sahilchanna.habits.data.Habit
import com.sahilchanna.habits.model.Achievements
import com.sahilchanna.habits.model.DayWindow
import com.sahilchanna.habits.model.HabitDays
import com.sahilchanna.habits.model.HabitType
import com.sahilchanna.habits.model.StatsRange
import com.sahilchanna.habits.model.Streaks
import com.sahilchanna.habits.ui.HabitsViewModel
import com.sahilchanna.habits.ui.components.CommentText
import com.sahilchanna.habits.ui.components.HabitGlyph
import com.sahilchanna.habits.ui.components.MutedGrey
import com.sahilchanna.habits.ui.components.PromptHeader
import com.sahilchanna.habits.ui.components.TermBar
import com.sahilchanna.habits.ui.components.TermSegmentBar
import com.sahilchanna.habits.ui.components.TermText
import com.sahilchanna.habits.ui.theme.LocalTerminalTheme
import com.sahilchanna.habits.ui.theme.TerminalTheme
import com.sahilchanna.habits.ui.theme.parseHex
import java.time.LocalDate

/**
 * The stats tab (§4.2) — overview plus a per-habit deep dive.
 *
 * Like the iOS build, every figure here is derived from completion history on each render; nothing
 * is stored. Ranges are expressed in whole weeks so the heatmap's columns are weeks and its rows are
 * weekdays — a "last N days" grid whose columns are not weekdays reads as a calendar while quietly
 * not being one.
 */
@Composable
fun StatsScreen(viewModel: HabitsViewModel, modifier: Modifier = Modifier) {
    val theme = LocalTerminalTheme.current
    val graph by viewModel.graph.collectAsState()
    val username by viewModel.username.collectAsState()
    val symbol by viewModel.promptSymbol.collectAsState()

    // Two independent segments with two independent ranges: the overview is a long-range density
    // view, the habit dive goes down to a single week.
    var segment by remember { mutableStateOf(0) }
    var selectedHabitId by remember { mutableStateOf<String?>(null) }

    val habits = graph.allHabits
    val today = viewModel.today

    Column(modifier.fillMaxSize().background(theme.bg)) {
        Column(Modifier.padding(horizontal = 16.dp).padding(top = 8.dp)) {
            PromptHeader(
                username = username,
                symbol = symbol,
                command = "stats",
                accent = theme.statsColor,
            )
            HorizontalDivider(Modifier.padding(top = 10.dp), color = theme.commentColor.copy(alpha = 0.4f))
        }

        SegmentBar(
            options = listOf("overview", "habits"),
            selection = segment,
            accent = theme.statsColor,
            onSelect = { segment = it },
        )

        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(16.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            if (segment == 0) {
                OverviewPanel(viewModel = viewModel, habits = habits)
            } else {
                HabitStatsPanel(
                    viewModel = viewModel,
                    habits = habits,
                    today = today,
                    selectedHabitId = selectedHabitId,
                    onSelect = { selectedHabitId = it },
                )
            }
        }
    }
}

/** Two text tabs in a bordered box, matching the iOS segment control's frame. */
@Composable
private fun SegmentBar(
    options: List<String>,
    selection: Int,
    accent: Color,
    onSelect: (Int) -> Unit,
) {
    val theme = LocalTerminalTheme.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp)
            .padding(top = 10.dp)
            .border(0.5.dp, theme.commentColor.copy(alpha = 0.3f), RoundedCornerShape(6.dp))
            .padding(3.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        options.forEachIndexed { index, label ->
            val isSelected = index == selection
            Box(
                modifier = Modifier
                    .weight(1f)
                    .background(
                        if (isSelected) accent.copy(alpha = 0.15f) else Color.Transparent,
                        RoundedCornerShape(5.dp),
                    )
                    .clickable { onSelect(index) }
                    .padding(vertical = 6.dp),
                contentAlignment = Alignment.Center,
            ) {
                TermText(
                    text = label,
                    size = 12f,
                    weight = if (isSelected) FontWeight.Bold else FontWeight.Normal,
                    color = if (isSelected) accent else theme.commentColor,
                )
            }
        }
    }
}

// MARK: - Overview

@Composable
private fun OverviewPanel(viewModel: HabitsViewModel, habits: List<Habit>) {
    val theme = LocalTerminalTheme.current
    val range by viewModel.statsRange.collectAsState()
    val clock = viewModel.clock
    val today = viewModel.today

    val completions = habits.flatMap { it.completions }
    val doneToday = habits.count { it.completion(today) != null }
    val currentStreak = Streaks.overall(completions, today)
    val best = habits.maxOfOrNull { Streaks.bestStreak(it) } ?: 0

    val rangeStart = DayWindow.rangeStart(range, habits, today, clock)
    val window = DayWindow.display(range, habits, today, clock)
    val windowDays = DayWindow.days(clock.mondayOf(rangeStart), today, rangeStart)
    val tally = HabitDays.tally(habits, windowDays, clock)

    // Before anything was tracked, a day was neither kept nor missed — rendering those as "missed"
    // would paint a wall of failure across the front of every long range.
    val trackingStart = habits.minOfOrNull { Achievements.firstTrackedDay(it, clock) } ?: today

    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        StatGrid(
            first = listOf("[today]" to doneToday.toString(), "[streak]" to currentStreak.toString()),
            second = listOf("[best]" to best.toString(), "[total]" to completions.size.toString()),
        )

        TermSegmentBar(
            options = StatsRange.overview.map { it.raw to it.raw },
            selection = range.raw,
            accent = theme.statsColor,
            onSelect = { viewModel.selectStatsRange(StatsRange.fromRaw(it)) },
        )

        SectionCard {
            CommentText(text = "// completions · ${window.label(range)}", size = 11f)
            Spacer(Modifier.height(8.dp))
            WeekHeatmap(
                window = window,
                today = today,
                ratio = { day -> if (day < trackingStart) -1.0 else Streaks.dayRatio(day, habits, clock) },
                accent = theme.statsColor,
            )
        }

        SectionCard {
            CommentText(text = "// by weekday", size = 11f)
            Spacer(Modifier.height(8.dp))
            WeekdayBreakdown(habits = habits, window = window, clock = clock)
        }

        Row(verticalAlignment = Alignment.CenterVertically) {
            CommentText(text = "${tally.done}/${tally.due} habit-days", size = 11f)
            Spacer(Modifier.weight(1f))
            TermText(
                text = "${(tally.rate * 100).toInt()}% over ${range.raw}",
                size = 11f,
                weight = FontWeight.SemiBold,
                color = theme.statsColor,
            )
        }
    }
}

/** `[today] 3 [streak] 7` over two rows of label/value cells. */
@Composable
private fun StatGrid(first: List<Pair<String, String>>, second: List<Pair<String, String>>) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        listOf(first, second).forEach { row ->
            Row(Modifier.fillMaxWidth()) {
                row.forEach { (label, value) ->
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        TermText(text = label, size = 11f, color = MutedGrey)
                        TermText(text = value, size = 18f, weight = FontWeight.Bold)
                    }
                }
            }
        }
    }
}

// MARK: - Week-aligned heatmap

/**
 * Weeks across, weekdays down — the only layout where a column means a week and a row means a
 * weekday. Cell size follows the column count so the grid fills the card at every range.
 */
@Composable
fun WeekHeatmap(
    window: DayWindow.Window,
    today: LocalDate,
    ratio: (LocalDate) -> Double,
    accent: Color,
    showLegend: Boolean = true,
) {
    val theme = LocalTerminalTheme.current
    val columns = DayWindow.grid(window.from, window.to, window.start)
    if (columns.isEmpty()) return
    val letters = listOf("M", "T", "W", "T", "F", "S", "S")

    BoxWithConstraints(Modifier.fillMaxWidth()) {
        // Sized from the width we actually have rather than a guess: the iOS build hardcoded a
        // 300pt content budget for a known phone width, which is exactly the assumption Android's
        // range of screens punishes. The floor on `cell` (2dp) still stops a year's 53 columns
        // from collapsing to nothing.
        val gap = if (columns.size > 20) 1.5.dp else 3.dp
        val labelWidth = 12.dp
        val legendWidth = if (showLegend) 30.dp else 0.dp
        val gaps = gap * (columns.size + if (showLegend) 2 else 1)
        val grid = maxWidth - labelWidth - legendWidth - gaps
        val cell = (grid / columns.size).coerceIn(2.dp, 26.dp)

        Row(horizontalArrangement = Arrangement.spacedBy(gap), verticalAlignment = Alignment.Top) {
            Column(verticalArrangement = Arrangement.spacedBy(gap)) {
                letters.forEach { letter ->
                    Box(Modifier.width(labelWidth).height(cell), contentAlignment = Alignment.Center) {
                        TermText(text = letter, size = 8f, color = theme.commentColor)
                    }
                }
            }
            columns.forEach { column ->
                Column(verticalArrangement = Arrangement.spacedBy(gap)) {
                    column.forEach { day -> HeatCell(day, cell, today, ratio, accent, theme) }
                }
            }
            if (showLegend) {
                HeatLegend(cell, accent, theme)
            }
        }
    }
}

/**
 * One day's square.
 *
 * The three states are deliberately distinguishable: a rest day (nothing was scheduled) is a faint
 * wash, a day that was due and missed is a darker grey, and a day that was done is the habit's own
 * colour at a strength proportional to how much of it was completed.
 */
@Composable
private fun HeatCell(
    day: LocalDate?,
    size: Dp,
    today: LocalDate,
    ratio: (LocalDate) -> Double,
    accent: Color,
    theme: TerminalTheme,
) {
    if (day == null) {
        // Outside the range: keep the shape, claim nothing.
        Box(Modifier.size(size))
        return
    }
    val r = ratio(day)
    val fill = when {
        r < 0 -> theme.commentColor.copy(alpha = 0.12f)
        r <= 0.0 -> theme.commentColor.copy(alpha = 0.25f)
        else -> accent.copy(alpha = (0.25f + 0.75f * r.toFloat()).coerceAtMost(1f))
    }
    // Proportional corners would round a 3dp square into a dot, so the radius has a floor.
    val shape = RoundedCornerShape(maxOf(0.5.dp, size * 0.18f))
    val base = Modifier.size(size).background(fill, shape)
    // Today gets a ring, but only where the cell is large enough for it to read as a ring rather
    // than as the whole cell.
    Box(if (day == today && size >= 8.dp) base.border(1.dp, accent, shape) else base)
}

@Composable
private fun HeatLegend(cell: Dp, accent: Color, theme: TerminalTheme) {
    Column(
        modifier = Modifier.padding(start = 5.dp),
        horizontalAlignment = Alignment.End,
        verticalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        TermText(text = "more", size = 8f, color = theme.commentColor)
        listOf(1.0f, 0.6f, 0.3f, 0.0f).forEach { level ->
            Box(
                Modifier
                    .size(cell * 0.7f)
                    .background(
                        if (level == 0f) theme.commentColor.copy(alpha = 0.25f)
                        else accent.copy(alpha = 0.25f + 0.75f * level),
                        RoundedCornerShape(2.dp),
                    ),
            )
        }
        TermText(text = "less", size = 8f, color = theme.commentColor)
    }
}

// MARK: - Weekday breakdown

/**
 * Completion rate per weekday across the window — the question a heatmap cannot answer at a
 * glance: *which* days you actually skip. The weakest weekday is flagged rather than left for the
 * reader to spot by comparing seven percentages.
 */
@Composable
private fun WeekdayBreakdown(habits: List<Habit>, window: DayWindow.Window, clock: com.sahilchanna.habits.model.HabitsClock) {
    val theme = LocalTerminalTheme.current
    val labels = listOf("M", "T", "W", "T", "F", "S", "S")
    val weekdays = listOf(2, 3, 4, 5, 6, 7, 1)
    val days = DayWindow.days(window.from, window.to, window.start)

    // Named `DayRow` rather than `Row`: a local class shadows the layout composable in this scope,
    // and `Row(verticalAlignment = ...)` below would then resolve to this constructor instead.
    data class DayRow(val label: String, val tally: HabitDays.Tally)

    val rows = weekdays.mapIndexed { index, weekday ->
        val matching = days.filter { Streaks.weekdayIndex(it) == weekday }
        DayRow(labels[index], HabitDays.tally(habits, matching, clock))
    }
    val worst = rows.filter { it.tally.due > 0 }.minByOrNull { it.tally.rate }

    Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
        rows.forEach { row ->
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Box(Modifier.width(10.dp)) {
                    TermText(text = row.label, size = 11f, weight = FontWeight.SemiBold, color = theme.commentColor)
                }
                Box(Modifier.weight(1f)) {
                    TermBar(fraction = row.tally.rate, color = theme.statsColor, height = 6.dp)
                }
                TermText(
                    text = if (row.tally.due > 0) "${(row.tally.rate * 100).toInt()}%" else "—",
                    size = 10f,
                    color = when {
                        row.tally.due == 0 -> theme.commentColor
                        worst != null && row === worst -> parseHex("#FF9F45")
                        else -> Color.White
                    },
                )
            }
        }
    }
}

// MARK: - Per-habit deep dive

@Composable
private fun HabitStatsPanel(
    viewModel: HabitsViewModel,
    habits: List<Habit>,
    today: LocalDate,
    selectedHabitId: String?,
    onSelect: (String) -> Unit,
) {
    val theme = LocalTerminalTheme.current
    val range by viewModel.habitRange.collectAsState()
    val clock = viewModel.clock

    if (habits.isEmpty()) {
        CommentText(text = "// no habits yet")
        return
    }
    val active = habits.firstOrNull { it.id == selectedHabitId } ?: habits.first()

    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        HabitChipBar(habits = habits, selectedId = active.id, onSelect = onSelect)

        TermSegmentBar(
            options = StatsRange.habit.map { it.raw to it.raw },
            selection = range.raw,
            accent = theme.statsColor,
            onSelect = { viewModel.selectHabitRange(StatsRange.fromRaw(it)) },
        )

        SummaryCard(habit = active, clock = clock)
        CompletionsCard(habit = active, range = range, today = today, clock = clock)

        // Seven days is a row, not a matrix: as whole-week columns the shortest range is one or two
        // slivers of 44dp squares running off the bottom of the screen.
        val isWeek = range == StatsRange.D7
        val window = DayWindow.display(range, habits, today, clock)
        SectionCard {
            CommentText(
                text = "// ${active.name} · ${if (isWeek) "this week" else window.label(range)}",
                size = 11f,
            )
            Spacer(Modifier.height(8.dp))
            if (isWeek) {
                HabitWeekRow(habit = active, today = today, clock = clock)
            } else {
                WeekHeatmap(
                    window = window,
                    today = today,
                    ratio = { day ->
                        val weekday = Streaks.weekdayIndex(day)
                        // Off-schedule days and days before the habit existed are rest days, not
                        // misses — only a day that was actually due can be failed.
                        if (!active.scheduleDays.contains(weekday) ||
                            day < Achievements.firstTrackedDay(active, clock)
                        ) {
                            -1.0
                        } else if (active.completion(day) != null) {
                            1.0
                        } else {
                            0.0
                        }
                    },
                    accent = parseHex(active.color.hex),
                    showLegend = false,
                )
            }
        }
    }
}

/** One habit's current Mon–Sun week, as a row of cells — the shape that fits seven days. */
@Composable
private fun HabitWeekRow(habit: Habit, today: LocalDate, clock: com.sahilchanna.habits.model.HabitsClock) {
    val theme = LocalTerminalTheme.current
    val letters = listOf("M", "T", "W", "T", "F", "S", "S")
    val accent = parseHex(habit.color.hex)
    val week = clock.weekDates(today)

    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(5.dp)) {
        week.forEachIndexed { index, day ->
            val isFuture = day > today
            val due = !isFuture &&
                habit.scheduleDays.contains(Streaks.weekdayIndex(day)) &&
                day >= Achievements.firstTrackedDay(habit, clock)
            val done = due && habit.completion(day) != null
            val fill = when {
                isFuture -> Color.Transparent
                done -> accent
                due -> theme.commentColor.copy(alpha = 0.28f)
                else -> theme.commentColor.copy(alpha = 0.12f)
            }
            val stroke = when {
                day == today -> accent
                isFuture -> theme.commentColor.copy(alpha = 0.18f)
                else -> Color.Transparent
            }
            Column(
                modifier = Modifier.weight(1f),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                TermText(text = letters[index], size = 9f, color = theme.commentColor)
                Box(
                    Modifier
                        .fillMaxWidth()
                        .height(38.dp)
                        .background(fill, RoundedCornerShape(5.dp))
                        .border(1.dp, stroke, RoundedCornerShape(5.dp)),
                )
            }
        }
    }
}

/**
 * Terminal-styled habit selector, replacing a system dropdown — the app avoids system pickers
 * everywhere else (§5.1), and a menu cannot show the habit's own colour.
 */
@Composable
private fun HabitChipBar(habits: List<Habit>, selectedId: String?, onSelect: (String) -> Unit) {
    val theme = LocalTerminalTheme.current
    Row(
        modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        habits.forEach { habit ->
            val isSelected = habit.id == selectedId
            val accent = parseHex(habit.color.hex)
            Row(
                modifier = Modifier
                    .background(
                        if (isSelected) accent.copy(alpha = 0.16f) else Color.Transparent,
                        RoundedCornerShape(5.dp),
                    )
                    .border(
                        0.5.dp,
                        if (isSelected) accent.copy(alpha = 0.6f) else theme.commentColor.copy(alpha = 0.3f),
                        RoundedCornerShape(5.dp),
                    )
                    .clickable { onSelect(habit.id) }
                    .padding(horizontal = 8.dp, vertical = 5.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(5.dp),
            ) {
                HabitGlyph(icon = habit.icon, name = habit.name, color = if (isSelected) accent else theme.commentColor)
                TermText(
                    text = habit.name,
                    size = 12f,
                    weight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal,
                    color = if (isSelected) accent else theme.commentColor,
                )
            }
        }
    }
}

@Composable
private fun SummaryCard(habit: Habit, clock: com.sahilchanna.habits.model.HabitsClock) {
    val theme = LocalTerminalTheme.current
    SectionCard {
        CommentText(text = "// summary", size = 11f)
        Spacer(Modifier.height(8.dp))
        TermKeyValueRow("mode", if (habit.type == HabitType.TIMED) "timed (${habit.targetLabel})" else "manual")
        TermKeyValueRow("schedule", scheduleLabel(habit))
        TermKeyValueRow("streak", Streaks.habitStreak(habit, clock.today()).toString())
        TermKeyValueRow("best", Streaks.bestStreak(habit).toString())
        TermKeyValueRow("since", formatShortDate(Achievements.firstTrackedDay(habit, clock)))
    }
}

/**
 * The habit's real schedule — `daily` / `weekdays` / `weekends` / `M·W·F`.
 *
 * The iOS build hardcoded this to "daily" for a while, which was a lie for anything scheduled less
 * often; the label is derived from the actual day set here.
 */
private fun scheduleLabel(habit: Habit): String {
    val days = habit.scheduleDays
    return when {
        days.size == 7 -> "daily"
        days.isEmpty() -> "unscheduled"
        days == setOf(2, 3, 4, 5, 6) -> "weekdays"
        days == setOf(1, 7) -> "weekends"
        else -> {
            val names = mapOf(2 to "M", 3 to "T", 4 to "W", 5 to "T", 6 to "F", 7 to "S", 1 to "S")
            listOf(2, 3, 4, 5, 6, 7, 1).filter { days.contains(it) }.mapNotNull { names[it] }
                .joinToString("·")
        }
    }
}

@Composable
private fun CompletionsCard(
    habit: Habit,
    range: StatsRange,
    today: LocalDate,
    clock: com.sahilchanna.habits.model.HabitsClock,
) {
    val theme = LocalTerminalTheme.current
    // The denominator is days the habit was actually due — bounded by the range *and* by when it
    // started being tracked. Counting raw calendar days reports `8/64` for a habit ten days old.
    val start = range.days?.let { today.minusDays((it - 1).toLong()) }
        ?: Achievements.firstTrackedDay(habit, clock)
    val tally = HabitDays.tally(listOf(habit), DayWindow.contiguous(start, today), clock)
    val logged = habit.completions.count { it.day >= start }

    SectionCard {
        CommentText(text = "// completions", size = 11f)
        Spacer(Modifier.height(8.dp))
        TermKeyValueRow("logged", logged.toString())
        TermKeyValueRow("rate", "${(tally.rate * 100).toInt()}%")
        TermKeyValueRow("days", "${tally.done}/${tally.due}")
        Spacer(Modifier.height(8.dp))
        TermBar(fraction = tally.rate, color = theme.statsColor)
    }
}

// MARK: - Shared

/** A bordered card — the shape every panel on this screen takes. */
@Composable
private fun SectionCard(content: @Composable () -> Unit) {
    val theme = LocalTerminalTheme.current
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .border(0.5.dp, theme.commentColor.copy(alpha = 0.3f), RoundedCornerShape(6.dp))
            .padding(12.dp),
    ) { content() }
}

@Composable
private fun TermKeyValueRow(key: String, value: String) {
    Row(Modifier.fillMaxWidth().padding(vertical = 2.dp), verticalAlignment = Alignment.CenterVertically) {
        TermText(text = key, size = 12f, color = MutedGrey)
        Spacer(Modifier.weight(1f))
        TermText(text = value, size = 12f, weight = FontWeight.SemiBold)
    }
}

/** `9 Mar 2026` — the abbreviated form the summary and completion cards print. */
private fun formatShortDate(day: LocalDate): String =
    "${day.dayOfMonth} ${day.month.name.lowercase().take(3).replaceFirstChar { it.uppercase() }} ${day.year}"
