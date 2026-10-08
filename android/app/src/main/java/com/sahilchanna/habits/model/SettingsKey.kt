package com.sahilchanna.habits.model

/**
 * Every preference key in one place, matching the iOS `SettingsKey` list plus the two this
 * port adds: the day-reset hour and the timer-notification display fields (Android has no
 * ActivityKit, so an ongoing notification stands in for the live activity and needs its own
 * display switches).
 */
object SettingsKey {
    const val USERNAME = "username"
    const val THEME_ID = "themeId"
    const val PROMPT_SYMBOL = "promptSymbol"
    const val TEXT_SIZE = "textSize"
    const val CROSS_OUT_COMPLETED = "crossOutCompleted"
    const val MOVE_COMPLETED_TO_BOTTOM = "moveCompletedToBottom"
    const val CUSTOM_THEMES = "customThemes.v1"
    const val SEEDED = "seeded.v1"
    const val DEMO_HISTORY_REMOVED = "demoHistoryRemoved.v1"
    const val COMPLETION_DAYS_ANCHORED = "completionDaysAnchored.v1"
    const val WATER_REMINDERS_ENABLED = "waterRemindersEnabled"
    const val WATER_START_HOUR = "waterStartHour"
    const val WATER_END_HOUR = "waterEndHour"
    const val WATER_INTERVAL = "waterIntervalMinutes"

    // Android-only, replacing the live-activity switches.
    const val DAY_RESET_HOUR = "dayResetHour"
    const val TIMER_NOTIFICATIONS_ENABLED = "timerNotificationsEnabled"
    const val TIMER_SHOW_TIMER = "timerShowTimer"
    const val TIMER_SHOW_PROGRESS = "timerShowProgress"
    const val TIMER_SHOW_NAME = "timerShowName"
    const val TIMER_COUNT_DOWN = "timerCountDown"
}

/** Base monospace size × scale, the three text sizes profile offers. */
object TextScale {
    fun multiplier(tier: Int): Float = listOf(1.0f, 1.18f, 1.36f)[tier.coerceIn(0, 2)]
}
