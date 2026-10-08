package com.sahilchanna.habits.ui.screens

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
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
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.sahilchanna.habits.model.Achievements
import com.sahilchanna.habits.ui.HabitsViewModel
import com.sahilchanna.habits.ui.components.CommentText
import com.sahilchanna.habits.ui.components.MutedGrey
import com.sahilchanna.habits.ui.components.PromptHeader
import com.sahilchanna.habits.ui.components.TermBar
import com.sahilchanna.habits.ui.components.TermText
import com.sahilchanna.habits.ui.theme.LocalTerminalTheme

/**
 * `$ achievements` — the tiers, milestones and XP total (§4.3.2).
 *
 * Pushed from the profile tab rather than given a fourth tab of its own: profile is the settings
 * tab, and a screen reached a few times a month does not deserve a permanent slot in the bar. The
 * chrome matches the rest of the app — a `[← back]` row rather than a system nav bar.
 */
@Composable
fun AchievementsScreen(viewModel: HabitsViewModel, onBack: () -> Unit, modifier: Modifier = Modifier) {
    val theme = LocalTerminalTheme.current
    val graph by viewModel.graph.collectAsState()
    val username by viewModel.username.collectAsState()
    val symbol by viewModel.promptSymbol.collectAsState()

    // Reading `graph` is what makes this recompute; the snapshot itself is derived from it.
    graph.allHabits.size
    val snapshot = viewModel.achievements()

    Column(modifier.fillMaxSize().background(theme.bg)) {
        Column(Modifier.padding(horizontal = 16.dp).padding(top = 8.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Row(
                    modifier = Modifier.clickable { onBack() },
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    TermText(text = "‹", size = 13f, weight = FontWeight.Bold, color = theme.commentColor)
                    TermText(text = "back", size = 11f, color = theme.commentColor)
                }
                Spacer(Modifier.weight(1f))
                XPChip(level = snapshot.level, accent = theme.profileColor, comment = theme.commentColor)
            }
            PromptHeader(
                username = username,
                symbol = symbol,
                command = "achievements",
                accent = theme.profileColor,
                modifier = Modifier.padding(top = 8.dp),
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
            LevelCard(level = snapshot.level)
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                CommentText(text = "// tier progress", size = 11f)
                snapshot.metrics.forEach { MetricCard(it) }
            }
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    CommentText(text = "// milestones", size = 11f)
                    Spacer(Modifier.weight(1f))
                    TermText(
                        text = "${snapshot.earnedMilestones}/${snapshot.milestones.size}",
                        size = 11f,
                        weight = FontWeight.SemiBold,
                        color = theme.profileColor,
                    )
                }
                Column(verticalArrangement = Arrangement.spacedBy(9.dp)) {
                    snapshot.milestones.forEach { MilestoneRow(it, theme.profileColor, theme.commentColor) }
                }
            }
            CommentText(text = "// derived from your completion history", size = 11f)
        }
    }
}

/** `[lvl 4] 412xp` — the global XP total. */
@Composable
fun XPChip(level: Achievements.LevelInfo, accent: Color, comment: Color = MutedGrey) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
        TermText(text = "[lvl ${level.level}]", size = 11f, weight = FontWeight.SemiBold, color = accent)
        TermText(text = "${level.xp}xp", size = 11f, color = comment)
    }
}

@Composable
private fun LevelCard(level: Achievements.LevelInfo) {
    val theme = LocalTerminalTheme.current
    // The bar fills on arrival rather than sitting full — the one moment the screen has to show
    // what the number means.
    val shown by animateFloatAsState(
        targetValue = level.fraction.toFloat(),
        animationSpec = tween(durationMillis = 700),
        label = "level",
    )
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .border(0.5.dp, theme.profileColor.copy(alpha = 0.45f), RoundedCornerShape(6.dp))
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            TermText(text = "[lvl ${level.level}]", size = 20f, weight = FontWeight.Bold, color = theme.profileColor)
            Spacer(Modifier.weight(1f))
            TermText(text = "${level.xp} xp", size = 13f, weight = FontWeight.SemiBold)
        }
        TermBar(fraction = shown.toDouble(), color = theme.profileColor)
        Row(verticalAlignment = Alignment.CenterVertically) {
            TermText(text = "${level.intoLevel}/${level.levelSpan} xp", size = 11f, color = theme.commentColor)
            Spacer(Modifier.weight(1f))
            TermText(
                text = "${level.toNextLevel} to lvl ${level.level + 1}",
                size = 11f,
                color = theme.commentColor,
            )
        }
    }
}

/** One metric's tier ladder: the current value, the bar, and the five shells along the way. */
@Composable
private fun MetricCard(progress: Achievements.MetricProgress) {
    val theme = LocalTerminalTheme.current
    val accent = theme.profileColor
    // A longer delay than the level card's, so the four bars do not all snap at once.
    val shown by animateFloatAsState(
        targetValue = progress.fraction.toFloat(),
        animationSpec = tween(durationMillis = 700, delayMillis = 60),
        label = progress.metric.raw,
    )

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .border(0.5.dp, theme.commentColor.copy(alpha = 0.3f), RoundedCornerShape(6.dp))
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            TermText(text = progress.metric.label, size = 13f)
            Spacer(Modifier.weight(1f))
            TermText(text = progress.current.toString(), size = 15f, weight = FontWeight.Bold, color = accent)
        }
        CommentText(text = progress.metric.comment, size = 11f)
        TermBar(fraction = shown.toDouble(), color = accent)
        TierLadder(progress = progress, accent = accent, theme = theme)
        Row(verticalAlignment = Alignment.CenterVertically) {
            TermText(
                text = progress.transition,
                size = 11f,
                weight = FontWeight.SemiBold,
                color = if (progress.isMaxed) accent else theme.fg,
            )
            Spacer(Modifier.weight(1f))
            // `63/150 · +150 xp`, or the tally once the ladder is finished.
            val threshold = progress.nextThreshold
            val reward = progress.nextReward
            TermText(
                text = if (threshold == null || reward == null) {
                    "maxed · ${progress.xpEarned}xp"
                } else {
                    "${progress.current}/$threshold · +$reward xp"
                },
                size = 11f,
                color = theme.commentColor,
            )
        }
    }
}

@Composable
private fun TierLadder(progress: Achievements.MetricProgress, accent: Color, theme: com.sahilchanna.habits.ui.theme.TerminalTheme) {
    Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
        Achievements.Tier.all.forEach { tier ->
            val earned = progress.earnedTiers.contains(tier)
            val isNext = progress.nextTier == tier
            TermText(
                text = if (earned) "✓${tier.tierName}" else tier.tierName,
                size = 10f,
                weight = if (earned) FontWeight.SemiBold else FontWeight.Normal,
                color = when {
                    earned -> accent
                    isNext -> theme.fg
                    else -> theme.commentColor
                },
                modifier = Modifier
                    .background(
                        if (earned) accent.copy(alpha = 0.16f) else Color.Transparent,
                        RoundedCornerShape(4.dp),
                    )
                    .border(
                        0.5.dp,
                        when {
                            earned -> accent.copy(alpha = 0.5f)
                            isNext -> theme.commentColor.copy(alpha = 0.7f)
                            else -> theme.commentColor.copy(alpha = 0.25f)
                        },
                        RoundedCornerShape(4.dp),
                    )
                    .padding(horizontal = 5.dp, vertical = 3.dp),
            )
        }
        Spacer(Modifier.weight(1f, fill = false))
    }
}

@Composable
private fun MilestoneRow(state: Achievements.MilestoneState, accent: Color, comment: Color) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        TermText(
            text = if (state.earned) "[✓]" else "[ ]",
            size = 12f,
            weight = FontWeight.SemiBold,
            color = if (state.earned) accent else comment,
        )
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
            TermText(
                text = state.name,
                size = 12f,
                weight = if (state.earned) FontWeight.SemiBold else FontWeight.Normal,
                color = if (state.earned) Color.White else comment,
            )
            CommentText(text = state.comment, size = 10f)
        }
        Spacer(Modifier.width(8.dp))
        TermText(
            text = "+${state.xp}",
            size = 11f,
            weight = FontWeight.SemiBold,
            color = if (state.earned) accent else comment.copy(alpha = 0.7f),
        )
    }
}
