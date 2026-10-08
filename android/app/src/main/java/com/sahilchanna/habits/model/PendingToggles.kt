package com.sahilchanna.habits.model

import com.sahilchanna.habits.data.Storage
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import java.time.LocalDate

/**
 * A state change made from a widget or a notification, waiting for the app to fold into the
 * store. The widget runs in a different process and cannot open the database, so it records the
 * desired state here; the app applies it before its next snapshot publish.
 */
@Serializable
data class PendingToggle(
    val habitId: String,
    /** The completion day, as an epoch day — a calendar date, not an instant. */
    val dayEpochDay: Long,
    val done: Boolean = false,
    val atMillis: Long = 0,
    /** Set by the notification's "discard": stop the running timer, log nothing. */
    val stopTimer: Boolean = false,
    /** Set by the notification's pause/resume key: the desired paused state. */
    val pause: Boolean? = null,
    /**
     * Set by "log glass": how many glasses to *add* to the day. Water is the one habit measured in
     * a count rather than a tick, so its completion's `value` is a glass tally — and logging a
     * glass is an increment, not a state, which is why it cannot go through `done` (that no-ops
     * once the day is ticked off).
     */
    val glasses: Int? = null,
) {
    val day: LocalDate get() = LocalDate.ofEpochDay(dayEpochDay)
}

/**
 * The queue of those changes, in the app's own storage.
 *
 * The merge rules are the interesting part and are documented on `enqueue`; they are the reason
 * this is a class with a `Storage` behind it rather than a thin preferences wrapper — the whole
 * thing is exercised by the unit tests.
 */
class PendingToggleQueue(
    private val storage: Storage,
    private val key: String,
) {
    private val json = Json { ignoreUnknownKeys = true }

    fun load(): List<PendingToggle> {
        val raw = storage.getString(key) ?: return emptyList()
        return runCatching { json.decodeFromString<List<PendingToggle>>(raw) }.getOrDefault(emptyList())
    }

    /** Logs one (or more) glasses of water against the habit's day. */
    fun logGlass(habitId: String, day: LocalDate, count: Int = 1, nowMillis: Long = 0) {
        enqueue(PendingToggle(habitId = habitId, dayEpochDay = day.toEpochDay(), done = true, atMillis = nowMillis, glasses = count))
    }

    /**
     * Records the desired state for one habit/day. Tapping twice replaces the entry rather than
     * queueing a second toggle, so the result is always what's on screen.
     */
    fun set(habitId: String, day: LocalDate, done: Boolean, nowMillis: Long = 0) {
        enqueue(PendingToggle(habitId = habitId, dayEpochDay = day.toEpochDay(), done = done, atMillis = nowMillis))
    }

    /** Stops a running timer without logging it. */
    fun stopTimer(habitId: String, today: LocalDate, nowMillis: Long = 0) {
        enqueue(PendingToggle(habitId = habitId, dayEpochDay = today.toEpochDay(), done = false, atMillis = nowMillis, stopTimer = true))
    }

    /** Pauses or resumes a running timer without logging it. */
    fun setPaused(habitId: String, paused: Boolean, today: LocalDate, nowMillis: Long = 0) {
        enqueue(PendingToggle(habitId = habitId, dayEpochDay = today.toEpochDay(), done = false, atMillis = nowMillis, pause = paused))
    }

    private fun enqueue(entry: PendingToggle) {
        val list = load().toMutableList()
        val index = list.indexOfFirst { it.habitId == entry.habitId && it.dayEpochDay == entry.dayEpochDay }
        if (index >= 0) {
            // Merge instead of replacing wholesale: these calls express *different fields* of one
            // habit's day, and a tap of one kind erasing a queued tap of another is how a widget
            // tick used to vanish under the next timer-notification pause.
            //
            //   stopTimer  — "discard": log nothing, so it supersedes everything queued.
            //   pause      — touches only the pause state; done and glasses survive.
            //   glasses    — accumulate (two "log glass" taps are two glasses, not one), and the
            //                first glass still ticks the day.
            //   plain done — replaces the done-state, which is a state rather than a quantity.
            val existing = list[index]
            list[index] = when {
                entry.stopTimer -> PendingToggle(entry.habitId, entry.dayEpochDay, done = false, atMillis = entry.atMillis, stopTimer = true)
                entry.pause != null -> existing.copy(pause = entry.pause)
                entry.glasses != null -> existing.copy(
                    glasses = (existing.glasses ?: 0) + entry.glasses,
                    done = existing.done || entry.done,
                )
                else -> existing.copy(done = entry.done)
            }
        } else {
            list.add(entry)
        }
        storage.putString(key, json.encodeToString(ListSerializer(PendingToggle.serializer()), list))
    }

    /** Returns the queued changes and clears them, so each is applied exactly once. */
    fun drain(): List<PendingToggle> {
        val list = load()
        if (list.isNotEmpty()) storage.remove(key)
        return list
    }

    fun clear() {
        storage.remove(key)
    }
}
