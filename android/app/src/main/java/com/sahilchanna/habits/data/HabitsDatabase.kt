package com.sahilchanna.habits.data

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.TypeConverters

@Database(
    entities = [Routine::class, Habit::class, Completion::class],
    version = 1,
    exportSchema = false,
)
@TypeConverters(Converters::class)
abstract class HabitsDatabase : RoomDatabase() {
    abstract fun routines(): RoutineDao
    abstract fun habits(): HabitDao
    abstract fun completions(): CompletionDao

    companion object {
        @Volatile
        private var instance: HabitsDatabase? = null

        fun get(context: Context): HabitsDatabase =
            instance ?: synchronized(this) {
                instance ?: Room.databaseBuilder(
                    context.applicationContext,
                    HabitsDatabase::class.java,
                    "habits.db",
                ).build().also { instance = it }
            }
    }
}
