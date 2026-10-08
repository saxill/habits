package com.sahilchanna.habits.model

/**
 * The two habit shapes the app knows. `checkbox` is a tick; `timed` logs real elapsed seconds
 * against a target.
 */
enum class HabitType(val raw: String, val label: String) {
    CHECKBOX("checkbox", "check-off"),
    TIMED("timed", "timed");

    companion object {
        fun from(raw: String?): HabitType = entries.firstOrNull { it.raw == raw } ?: CHECKBOX
    }
}

/**
 * The habit palette. Hex strings rather than Compose colors so the same value can be written
 * into a widget snapshot and re-parsed there, exactly as the iOS build does.
 */
enum class HabitColor(val raw: String, val hex: String) {
    CYAN("cyan", "#00D7C3"),
    BLUE("blue", "#5AA7FF"),
    PURPLE("purple", "#C084FC"),
    RED("red", "#FF6B6B"),
    GREEN("green", "#4ADE80"),
    AMBER("amber", "#FFB454");

    companion object {
        val DEFAULT = CYAN
        fun from(raw: String?): HabitColor = entries.firstOrNull { it.raw == raw } ?: DEFAULT
    }
}
