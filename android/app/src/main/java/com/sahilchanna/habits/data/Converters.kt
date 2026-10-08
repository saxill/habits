package com.sahilchanna.habits.data

import androidx.room.TypeConverter
import java.time.Instant

/**
 * Room stores an `Instant` as epoch millis. The completion's *day* is deliberately not an
 * instant at all — it is an epoch day held as a plain `Long`, because a calendar date is the
 * only form of "the 14th" that does not move when the device's zone does.
 */
class Converters {
    @TypeConverter
    fun instantToMillis(value: Instant?): Long? = value?.toEpochMilli()

    @TypeConverter
    fun millisToInstant(value: Long?): Instant? = value?.let(Instant::ofEpochMilli)
}
