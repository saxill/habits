package com.sahilchanna.habits.ui.components

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.Spring
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Brush
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Code
import androidx.compose.material.icons.filled.DarkMode
import androidx.compose.material.icons.filled.DirectionsRun
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FitnessCenter
import androidx.compose.material.icons.filled.Inbox
import androidx.compose.material.icons.filled.Laptop
import androidx.compose.material.icons.filled.LightMode
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.Medication
import androidx.compose.material.icons.filled.MenuBook
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.PhoneAndroid
import androidx.compose.material.icons.filled.Psychology
import androidx.compose.material.icons.filled.Restaurant
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.ShoppingCart
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.WaterDrop
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.sahilchanna.habits.model.Streaks
import com.sahilchanna.habits.ui.theme.LocalFontScale
import com.sahilchanna.habits.ui.theme.LocalTerminalTheme
import com.sahilchanna.habits.ui.theme.TerminalFont
import com.sahilchanna.habits.ui.theme.parseHex
import java.time.LocalDate

/** The muted grey every terminal comments, hints and inactive labels use. */
val MutedGrey = parseHex("#6E6E73")

/**
 * Monospace terminal text at a base size, scaled by the user's text-size setting.
 *
 * The one entry point for type in the app, so the "everything is monospace and everything scales"
 * rules hold without each screen remembering them.
 */
@Composable
fun TermText(
    text: String,
    modifier: Modifier = Modifier,
    size: Float = 13f,
    color: Color = Color.White,
    weight: FontWeight = FontWeight.Normal,
    textDecoration: TextDecoration? = null,
) {
    val scale = LocalFontScale.current
    Text(
        text = text,
        modifier = modifier,
        color = color,
        fontFamily = TerminalFont,
        fontWeight = weight,
        fontSize = (size * scale).sp,
        textDecoration = textDecoration,
    )
}

/**
 * `[✓]` / `[ ]` — the app's checkbox.
 *
 * The bracket is the whole state: there is no box to fill, so the only feedback that a tap landed
 * is the glyph swapping and its small spring. That is deliberate and it is why the animation is
 * here rather than on the row.
 */
@Composable
fun BracketCheckbox(checked: Boolean, color: Color = Color.White) {
    val scale by animateFloatAsState(
        targetValue = if (checked) 1f else 0.92f,
        animationSpec = spring(dampingRatio = 0.55f, stiffness = Spring.StiffnessMediumLow),
        label = "bracket",
    )
    TermText(
        text = if (checked) "[✓]" else "[ ]",
        size = 13f,
        weight = FontWeight.SemiBold,
        color = if (checked) color else MutedGrey,
        modifier = Modifier.scale(scale),
    )
}

/** A `// comment` line — the terminal voice for anything secondary. */
@Composable
fun CommentText(text: String, size: Float = 11f, modifier: Modifier = Modifier) {
    val theme = LocalTerminalTheme.current
    TermText(text = text, size = size, color = theme.commentColor, modifier = modifier)
}

/**
 * The screen header in prompt form: `user[pro]@init.Habits $ daily`.
 *
 * The iOS build drops the host when the line will not fit (`ViewThatFits`). Compose has no direct
 * equivalent, so the host is dropped by the caller when it has no room — the trailing slot is
 * always measured first, which is the same priority the iOS version gave it.
 */
@Composable
fun PromptHeader(
    username: String,
    symbol: String,
    command: String,
    accent: Color,
    modifier: Modifier = Modifier,
    compact: Boolean = false,
    trailing: (@Composable () -> Unit)? = null,
) {
    Row(
        modifier = modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        TermText(
            text = if (compact) "$username " else "$username[pro]@init.Habits ",
            size = 14f,
            weight = FontWeight.SemiBold,
            color = accent,
            modifier = Modifier.weight(1f, fill = false),
        )
        TermText(text = "$symbol ", size = 14f, weight = FontWeight.SemiBold, color = MutedGrey)
        TermText(
            text = command,
            size = 14f,
            weight = FontWeight.SemiBold,
            color = Color.White,
            modifier = Modifier.weight(1f, fill = false),
        )
        if (trailing != null) {
            Box(Modifier.weight(1f, fill = false)) { trailing() }
        }
    }
}

/**
 * Mon–Sun week strip with a per-day completion fill bar (§4.1).
 *
 * The ratio comes from `Streaks.dayRatio`, which is the single definition of "how much of this day
 * was done" — the same number the heatmap uses, so the strip and the grid can never disagree.
 */
@Composable
fun WeekStrip(
    week: List<LocalDate>,
    selected: LocalDate,
    today: LocalDate,
    habits: List<com.sahilchanna.habits.data.Habit>,
    onSelect: (LocalDate) -> Unit,
    modifier: Modifier = Modifier,
) {
    val theme = LocalTerminalTheme.current
    val letters = listOf("M", "T", "W", "T", "F", "S", "S")
    Row(modifier = modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        week.forEachIndexed { index, day ->
            val isSelected = day == selected
            val isToday = day == today
            val isFuture = day > today
            val ratio = Streaks.dayRatio(day, habits)
            Column(
                modifier = Modifier
                    .weight(1f)
                    .clickable { onSelect(day) },
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                TermText(
                    text = letters.getOrElse(index) { "?" },
                    size = 10f,
                    color = if (isSelected) theme.habitsColor else theme.commentColor,
                )
                Box(
                    modifier = Modifier
                        .background(
                            // Today gets a wash behind the number, but only while it is not the
                            // selected day — otherwise two highlights compete on one cell.
                            if (isToday && !isSelected) theme.habitsColor.copy(alpha = 0.25f) else Color.Transparent,
                            RoundedCornerShape(4.dp),
                        )
                        .padding(horizontal = 6.dp),
                ) {
                    TermText(
                        text = day.dayOfMonth.toString(),
                        size = 13f,
                        weight = FontWeight.SemiBold,
                        color = when {
                            isSelected -> theme.habitsColor
                            isFuture -> theme.commentColor
                            else -> Color.White
                        },
                    )
                }
                // The fill bar: dim for a future day, brighter with the share of the day done.
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(3.dp)
                        .background(
                            when {
                                ratio < 0 -> theme.commentColor.copy(alpha = 0.2f)
                                ratio <= 0 -> theme.commentColor.copy(alpha = 0.3f)
                                else -> theme.habitsColor.copy(alpha = (0.35f + 0.65f * ratio).toFloat())
                            },
                            RoundedCornerShape(2.dp),
                        ),
                )
            }
        }
    }
}

/** A terminal-styled segmented control — plain clickable text, no Material Picker quirks. */
@Composable
fun TermSegmentBar(
    options: List<Pair<String, String>>,
    selection: String,
    accent: Color,
    onSelect: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(modifier = modifier, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        options.forEach { (id, label) ->
            val isSelected = id == selection
            TermText(
                text = label,
                size = 11f,
                weight = if (isSelected) FontWeight.Bold else FontWeight.Normal,
                color = if (isSelected) accent else MutedGrey,
                modifier = Modifier
                    .background(
                        if (isSelected) accent.copy(alpha = 0.15f) else Color.Transparent,
                        RoundedCornerShape(4.dp),
                    )
                    .clickable { onSelect(id) }
                    .padding(horizontal = 8.dp, vertical = 4.dp),
            )
        }
    }
}

/**
 * A horizontal progress bar in the terminal's flat style.
 *
 * Hand-drawn rather than Material's `LinearProgressIndicator`: the stock one animates and rounds its
 * ends in a way that reads as a spinner, and this is a static measurement.
 */
@Composable
fun TermBar(fraction: Double, color: Color, modifier: Modifier = Modifier, height: androidx.compose.ui.unit.Dp = 6.dp) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(height)
            .background(color.copy(alpha = 0.18f), RoundedCornerShape(2.dp)),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth(fraction.coerceIn(0.0, 1.0).toFloat())
                .height(height)
                .background(color, RoundedCornerShape(2.dp)),
        )
    }
}

/** A label/value line — the shape most of the profile and stats rows take. */
@Composable
fun TermKeyValue(key: String, value: String, valueColor: Color = Color.White, modifier: Modifier = Modifier) {
    Row(modifier = modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        TermText(text = key, size = 12f, color = MutedGrey)
        Box(Modifier.weight(1f))
        TermText(text = value, size = 12f, color = valueColor)
    }
}

/**
 * A habit's glyph.
 *
 * SF Symbol names are what the store holds (they are the user's data and travel through the widget
 * snapshot), so this is the mapping to Android's icon set. A name with no mapping falls back to the
 * habit's first letter in a monospace face, which reads as intentional in a terminal UI rather than
 * as a missing image.
 */
@Composable
fun HabitGlyph(icon: String, name: String, color: Color, modifier: Modifier = Modifier) {
    val vector = habitIcon(icon)
    if (vector != null) {
        Icon(imageVector = vector, contentDescription = null, tint = color, modifier = modifier.size(16.dp))
    } else {
        TermText(
            text = name.take(1).ifEmpty { "?" },
            size = 13f,
            weight = FontWeight.SemiBold,
            color = color,
            modifier = modifier,
        )
    }
}

/**
 * SF Symbol name → Material icon.
 *
 * Deliberately conservative: only the names the app's own seed, icon picker and the iOS defaults
 * actually use are mapped. A guess at a symbol that is not in the set would be a compiler error at
 * best and a wrong picture at worst, and the letter fallback is a fine outcome for anything missed.
 */
fun habitIcon(icon: String): ImageVector? = when (icon) {
    "figure.flexibility", "figure.walk", "figure.run" -> Icons.Filled.DirectionsRun
    "drop" -> Icons.Filled.WaterDrop
    "book" -> Icons.Filled.MenuBook
    "square.and.pencil" -> Icons.Filled.Edit
    "brain.head.profile" -> Icons.Filled.Psychology
    "iphone.slash" -> Icons.Filled.PhoneAndroid
    "moon.zzz", "moon.stars" -> Icons.Filled.DarkMode
    "sun.max" -> Icons.Filled.LightMode
    "laptopcomputer" -> Icons.Filled.Laptop
    "tray" -> Icons.Filled.Inbox
    "checkmark" -> Icons.Filled.Check
    "flame" -> Icons.Filled.LocalFireDepartment
    "star" -> Icons.Filled.Star
    "heart" -> Icons.Filled.Favorite
    "bell" -> Icons.Filled.Notifications
    "clock" -> Icons.Filled.Schedule
    "cart" -> Icons.Filled.ShoppingCart
    "fork.knife" -> Icons.Filled.Restaurant
    "pills" -> Icons.Filled.Medication
    "dumbbell" -> Icons.Filled.FitnessCenter
    "music.note" -> Icons.Filled.MusicNote
    "paintbrush" -> Icons.Filled.Brush
    "terminal" -> Icons.Filled.Code
    else -> null
}

/**
 * The icon names the picker offers, in the order it shows them.
 *
 * The same strings the iOS picker used, so a habit created here and exported would keep its icon.
 */
val IconChoices: List<String> = listOf(
    "circle", "checkmark", "drop", "flame", "star", "heart", "book", "square.and.pencil",
    "brain.head.profile", "figure.flexibility", "dumbbell", "fork.knife", "pills", "cart",
    "laptopcomputer", "iphone.slash", "music.note", "paintbrush", "sun.max", "moon.zzz",
    "bell", "clock", "terminal",
)
