package com.sahilchanna.habits.data

import android.content.SharedPreferences
import android.content.Context
import com.sahilchanna.habits.model.SettingsKey

/**
 * The small key/value store the app keeps its preferences, its widget snapshot and its pending
 * widget toggles in — the same jobs `UserDefaults(suiteName:)` does for the iOS build.
 *
 * An interface rather than `SharedPreferences` directly, so the parts that make decisions (the
 * pending-toggle queue's merge rules above all) can be driven in a unit test with no Android
 * around them.
 */
interface Storage {
    fun getString(key: String): String?
    fun putString(key: String, value: String?)
    fun getInt(key: String, default: Int): Int
    fun putInt(key: String, value: Int)
    fun getLong(key: String, default: Long): Long
    fun putLong(key: String, value: Long)
    fun getBoolean(key: String, default: Boolean): Boolean
    fun putBoolean(key: String, value: Boolean)
    fun remove(key: String)
}

class PrefsStorage(private val prefs: SharedPreferences) : Storage {
    override fun getString(key: String): String? = prefs.getString(key, null)
    override fun putString(key: String, value: String?) {
        prefs.edit().putString(key, value).apply()
    }

    override fun getInt(key: String, default: Int): Int = prefs.getInt(key, default)
    override fun putInt(key: String, value: Int) {
        prefs.edit().putInt(key, value).apply()
    }

    override fun getLong(key: String, default: Long): Long = prefs.getLong(key, default)
    override fun putLong(key: String, value: Long) {
        prefs.edit().putLong(key, value).apply()
    }

    override fun getBoolean(key: String, default: Boolean): Boolean = prefs.getBoolean(key, default)
    override fun putBoolean(key: String, value: Boolean) {
        prefs.edit().putBoolean(key, value).apply()
    }

    override fun remove(key: String) {
        prefs.edit().remove(key).apply()
    }
}

/** An in-memory `Storage` for tests. */
class MemoryStorage(private val map: MutableMap<String, Any?> = mutableMapOf()) : Storage {
    override fun getString(key: String): String? = map[key] as? String
    override fun putString(key: String, value: String?) {
        if (value == null) map.remove(key) else map[key] = value
    }

    override fun getInt(key: String, default: Int): Int = map[key] as? Int ?: default
    override fun putInt(key: String, value: Int) {
        map[key] = value
    }

    override fun getLong(key: String, default: Long): Long = map[key] as? Long ?: default
    override fun putLong(key: String, value: Long) {
        map[key] = value
    }

    override fun getBoolean(key: String, default: Boolean): Boolean = map[key] as? Boolean ?: default
    override fun putBoolean(key: String, value: Boolean) {
        map[key] = value
    }

    override fun remove(key: String) {
        map.remove(key)
    }
}

/**
 * Typed access to every preference the app has, with the same defaults the iOS build ships.
 * Reading through one object is what keeps the keys from drifting apart across screens.
 */
class Settings(private val storage: Storage) {
    var username: String
        get() = storage.getString(SettingsKey.USERNAME) ?: "user"
        set(value) {
            storage.putString(SettingsKey.USERNAME, value.take(15))
        }

    var themeId: String
        get() = storage.getString(SettingsKey.THEME_ID) ?: "ansi-dark"
        set(value) {
            storage.putString(SettingsKey.THEME_ID, value)
        }

    var promptSymbol: String
        get() = storage.getString(SettingsKey.PROMPT_SYMBOL) ?: "$"
        set(value) {
            storage.putString(SettingsKey.PROMPT_SYMBOL, value)
        }

    /** 0/1/2 → default/larger/largest. */
    var textSize: Int
        get() = storage.getInt(SettingsKey.TEXT_SIZE, 0)
        set(value) {
            storage.putInt(SettingsKey.TEXT_SIZE, value.coerceIn(0, 2))
        }

    var crossOutCompleted: Boolean
        get() = storage.getBoolean(SettingsKey.CROSS_OUT_COMPLETED, true)
        set(value) {
            storage.putBoolean(SettingsKey.CROSS_OUT_COMPLETED, value)
        }

    var moveCompletedToBottom: Boolean
        get() = storage.getBoolean(SettingsKey.MOVE_COMPLETED_TO_BOTTOM, false)
        set(value) {
            storage.putBoolean(SettingsKey.MOVE_COMPLETED_TO_BOTTOM, value)
        }

    /**
     * Hour a completion day rolls over at. Zero is the iOS behaviour; anything later keeps a
     * small-hours session on the day it started.
     */
    var dayResetHour: Int
        get() = storage.getInt(SettingsKey.DAY_RESET_HOUR, 0)
        set(value) {
            storage.putInt(SettingsKey.DAY_RESET_HOUR, value.coerceIn(0, 23))
        }

    var timerNotificationsEnabled: Boolean
        get() = storage.getBoolean(SettingsKey.TIMER_NOTIFICATIONS_ENABLED, true)
        set(value) {
            storage.putBoolean(SettingsKey.TIMER_NOTIFICATIONS_ENABLED, value)
        }

    var showTimerInNotification: Boolean
        get() = storage.getBoolean(SettingsKey.TIMER_SHOW_TIMER, true)
        set(value) {
            storage.putBoolean(SettingsKey.TIMER_SHOW_TIMER, value)
        }

    var showProgressInNotification: Boolean
        get() = storage.getBoolean(SettingsKey.TIMER_SHOW_PROGRESS, true)
        set(value) {
            storage.putBoolean(SettingsKey.TIMER_SHOW_PROGRESS, value)
        }

    var showNameInNotification: Boolean
        get() = storage.getBoolean(SettingsKey.TIMER_SHOW_NAME, true)
        set(value) {
            storage.putBoolean(SettingsKey.TIMER_SHOW_NAME, value)
        }

    var countDown: Boolean
        get() = storage.getBoolean(SettingsKey.TIMER_COUNT_DOWN, true)
        set(value) {
            storage.putBoolean(SettingsKey.TIMER_COUNT_DOWN, value)
        }

    var seeded: Boolean
        get() = storage.getBoolean(SettingsKey.SEEDED, false)
        set(value) {
            storage.putBoolean(SettingsKey.SEEDED, value)
        }

    var demoHistoryRemoved: Boolean
        get() = storage.getBoolean(SettingsKey.DEMO_HISTORY_REMOVED, false)
        set(value) {
            storage.putBoolean(SettingsKey.DEMO_HISTORY_REMOVED, value)
        }

    var completionDaysAnchored: Boolean
        get() = storage.getBoolean(SettingsKey.COMPLETION_DAYS_ANCHORED, false)
        set(value) {
            storage.putBoolean(SettingsKey.COMPLETION_DAYS_ANCHORED, value)
        }

    var waterRemindersEnabled: Boolean
        get() = storage.getBoolean(SettingsKey.WATER_REMINDERS_ENABLED, false)
        set(value) {
            storage.putBoolean(SettingsKey.WATER_REMINDERS_ENABLED, value)
        }

    var waterStartHour: Int
        get() = storage.getInt(SettingsKey.WATER_START_HOUR, 9)
        set(value) {
            storage.putInt(SettingsKey.WATER_START_HOUR, value.coerceIn(0, 23))
        }

    var waterEndHour: Int
        get() = storage.getInt(SettingsKey.WATER_END_HOUR, 21)
        set(value) {
            storage.putInt(SettingsKey.WATER_END_HOUR, value.coerceIn(0, 23))
        }

    var waterIntervalMinutes: Int
        get() = storage.getInt(SettingsKey.WATER_INTERVAL, 120)
        set(value) {
            storage.putInt(SettingsKey.WATER_INTERVAL, value)
        }

    var customThemesJson: String?
        get() = storage.getString(SettingsKey.CUSTOM_THEMES)
        set(value) {
            storage.putString(SettingsKey.CUSTOM_THEMES, value)
        }
}

/** The app's default storage: one private preferences file, like the iOS app's defaults. */
object HabitsShared {
    const val SNAPSHOT_KEY = "habits.snapshot.v2"
    const val PENDING_TOGGLES_KEY = "habits.pendingToggles.v2"

    @Volatile
    private var storage: Storage? = null

    fun install(context: Context) {
        storage = PrefsStorage(context.applicationContext.getSharedPreferences("habits", Context.MODE_PRIVATE))
    }

    fun storage(): Storage = storage ?: error("HabitsShared.install() has not run")

    /**
     * The same storage, installing it if nobody has yet.
     *
     * A widget receiver or a notification action can start the process on its own, with no
     * `Application.onCreate` ahead of it to call `install`. Failing there would take down a
     * notification tap, so the components that might run first install on demand instead.
     */
    @Synchronized
    fun storageOrInstall(context: Context): Storage {
        storage?.let { return it }
        install(context)
        return storage()
    }

    fun settings(): Settings = Settings(storage())
}
