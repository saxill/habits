package com.sahilchanna.habits.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query
import androidx.room.Upsert
import kotlinx.coroutines.flow.Flow

/**
 * The DAOs are deliberately thin: the app's decisions live in `model/` where they can be tested
 * without Android, and these only move rows.
 */
@Dao
interface RoutineDao {
    @Query("SELECT * FROM routines ORDER BY sortIndex")
    fun observeAll(): Flow<List<Routine>>

    @Query("SELECT * FROM routines ORDER BY sortIndex")
    suspend fun all(): List<Routine>

    @Upsert
    suspend fun upsert(routine: Routine)

    @Query("DELETE FROM routines WHERE id = :id")
    suspend fun delete(id: String)
}

@Dao
interface HabitDao {
    @Query("SELECT * FROM habits ORDER BY sortIndex")
    fun observeAll(): Flow<List<Habit>>

    @Query("SELECT * FROM habits ORDER BY sortIndex")
    suspend fun all(): List<Habit>

    @Query("SELECT * FROM habits WHERE id = :id LIMIT 1")
    suspend fun byId(id: String): Habit?

    @Upsert
    suspend fun upsert(habit: Habit)

    @Query("DELETE FROM habits WHERE id = :id")
    suspend fun delete(id: String)
}

@Dao
interface CompletionDao {
    @Query("SELECT * FROM completions")
    fun observeAll(): Flow<List<Completion>>

    @Query("SELECT * FROM completions")
    suspend fun all(): List<Completion>

    @Query("SELECT * FROM completions WHERE habitId = :habitId AND dayEpochDay = :epochDay LIMIT 1")
    suspend fun forDay(habitId: String, epochDay: Long): Completion?

    @Insert
    suspend fun insert(completion: Completion)

    @Upsert
    suspend fun upsert(completion: Completion)

    @Query("DELETE FROM completions WHERE id = :id")
    suspend fun delete(id: String)

    /** Used by the legacy day-anchor migration, which has to rewrite a day in place. */
    @Query("UPDATE completions SET dayEpochDay = :epochDay, legacyDayMillis = NULL WHERE id = :id")
    suspend fun reanchor(id: String, epochDay: Long)
}
