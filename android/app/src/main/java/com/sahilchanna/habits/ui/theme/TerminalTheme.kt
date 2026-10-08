package com.sahilchanna.habits.ui.theme

import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.sp
import com.sahilchanna.habits.data.Settings
import com.sahilchanna.habits.model.SettingsKey
import com.sahilchanna.habits.model.TextScale
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json

/**
 * A terminal palette (§5.3).
 *
 * Three built-ins and any number of the user's own. Colors are stored as `#RRGGBB` strings rather
 * than Compose colors for one reason: they travel through the widget snapshot and the custom-theme
 * preference as plain text, and a `Color` would have to be re-serialized at both ends.
 */
@Serializable
data class TerminalTheme(
    val id: String,
    var name: String,
    var background: String,
    var foreground: String,
    var comment: String,
    var habitsAccent: String,
    var statsAccent: String,
    var profileAccent: String,
) {
    /** The theme editor only ever edits and deletes a user's own palettes, never a built-in. */
    val isCustom: Boolean get() = id.startsWith("custom-")

    val bg: Color get() = parseHex(background)
    val fg: Color get() = parseHex(foreground)
    val commentColor: Color get() = parseHex(comment)
    val habitsColor: Color get() = parseHex(habitsAccent)
    val statsColor: Color get() = parseHex(statsAccent)
    val profileColor: Color get() = parseHex(profileAccent)

    companion object {
        fun builtin(): List<TerminalTheme> = listOf(
            TerminalTheme(
                id = "ansi-dark", name = "ansi dark",
                background = "#000000", foreground = "#E8E8E8", comment = "#6E6E73",
                habitsAccent = "#FFB454", statsAccent = "#4ADE80", profileAccent = "#FF6BD6",
            ),
            TerminalTheme(
                id = "dracula", name = "dracula",
                background = "#282A36", foreground = "#F8F8F2", comment = "#6272A4",
                habitsAccent = "#FFB86C", statsAccent = "#50FA7B", profileAccent = "#FF79C6",
            ),
            TerminalTheme(
                id = "solarized-dark", name = "solarized dark",
                background = "#002B36", foreground = "#93A1A1", comment = "#586E75",
                habitsAccent = "#B58900", statsAccent = "#859900", profileAccent = "#D33682",
            ),
        )
    }
}

/**
 * `#RRGGBB` to a Compose color.
 *
 * Hand-parsed rather than through `android.graphics.Color.parseColor`, which throws on a malformed
 * string — and a hand-edited or truncated preference must render as *something*, not take the
 * screen down. Anything unreadable comes back as transparent, so the mistake is visible rather
 * than hidden behind a plausible default.
 */
fun parseHex(hex: String): Color {
    val s = hex.trim().removePrefix("#")
    if (s.length != 6) return Color.Transparent
    val value = s.toLongOrNull(16) ?: return Color.Transparent
    return Color(
        red = ((value shr 16) and 0xFF).toInt() / 255f,
        green = ((value shr 8) and 0xFF).toInt() / 255f,
        blue = (value and 0xFF).toInt() / 255f,
    )
}

/** The inverse, for the theme editor's hex fields. */
fun Color.toHexString(): String {
    val r = (red * 255f).toInt().coerceIn(0, 255)
    val g = (green * 255f).toInt().coerceIn(0, 255)
    val b = (blue * 255f).toInt().coerceIn(0, 255)
    return "#%02X%02X%02X".format(r, g, b)
}

/**
 * Built-ins plus the user's own palettes, read from and written to preferences.
 *
 * Not an `ObservableObject` like the iOS `ThemeStore`: a theme change here is made on the profile
 * screen and the whole tree recomposes from the view model's state, so there is nothing to notify.
 */
class ThemeStore(private val settings: Settings) {
    private val json = Json { ignoreUnknownKeys = true }

    val customThemes: List<TerminalTheme>
        get() {
            val raw = settings.customThemesJson ?: return emptyList()
            return runCatching { json.decodeFromString<List<TerminalTheme>>(raw) }.getOrDefault(emptyList())
        }

    val all: List<TerminalTheme> get() = TerminalTheme.builtin() + customThemes

    fun byId(id: String): TerminalTheme = all.firstOrNull { it.id == id } ?: all.first()

    fun upsert(theme: TerminalTheme) {
        val list = customThemes.toMutableList()
        val index = list.indexOfFirst { it.id == theme.id }
        if (index >= 0) list[index] = theme else list.add(theme)
        save(list)
    }

    fun delete(theme: TerminalTheme) {
        save(customThemes.filterNot { it.id == theme.id })
    }

    private fun save(themes: List<TerminalTheme>) {
        settings.customThemesJson = json.encodeToString(ListSerializer(TerminalTheme.serializer()), themes)
    }

    companion object {
        /** A copy gets a `custom-` id, which is what marks it as the user's own and editable. */
        fun duplicate(source: TerminalTheme, id: String): TerminalTheme = TerminalTheme(
            id = "custom-${id.take(8).lowercase()}",
            name = "${source.name} copy",
            background = source.background,
            foreground = source.foreground,
            comment = source.comment,
            habitsAccent = source.habitsAccent,
            statsAccent = source.statsAccent,
            profileAccent = source.profileAccent,
        )

        /** The blank palette a "new theme" starts from: the ansi-dark look, unnamed. */
        fun fresh(id: String): TerminalTheme = duplicate(TerminalTheme.builtin().first(), id)
            .copy(name = "new theme")
    }
}

/** The active theme, provided at the root and read by every screen. */
val LocalTerminalTheme = staticCompositionLocalOf { TerminalTheme.builtin().first() }

/**
 * The user's text-size multiplier. Provided separately from the theme because it is not a color:
 * it scales the monospace base size, and every `term()` call in the app reads it.
 */
val LocalFontScale = staticCompositionLocalOf { 1f }

/**
 * The terminal's one font.
 *
 * `FontFamily.Monospace` rather than a bundled typeface: on Android that resolves to the device's
 * monospace face, which is the platform's own terminal look and costs nothing in APK size. A
 * bundled font would render identically everywhere at the price of shipping a megabyte of glyphs
 * to say the same thing.
 */
val TerminalFont: FontFamily = FontFamily.Monospace

/** Base size × the user's scale — the one place a text size is computed. */
fun scaledSp(base: Float, scale: Float): TextUnit = (base * scale).sp

/** The three text sizes the profile screen offers, indexed to `Settings.textSize`. */
fun fontScaleFor(tier: Int): Float = TextScale.multiplier(tier)

/** The keys the theme and text settings live under, named once for the settings screen. */
object ThemeKeys {
    const val THEME_ID = SettingsKey.THEME_ID
}
