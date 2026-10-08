package com.sahilchanna.habits.data

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import java.time.LocalDate

/**
 * The loaded store: three flat lists with every relationship wired up, which is what the screens
 * and the derived math read. One instance of each habit is shared between its routine, its
 * completions and the list, exactly as SwiftData hands the iOS build the same object everywhere.
 */
class HabitsGraph(
    val routines: List<Routine>,
    val habits: List<Habit>,
    val completions: List<Completion>,
) {
    /** Habits filed under "none" — they live in no routine but still count everywhere. */
    val unfiledHabits: List<Habit> get() = habits.filter { it.routine == null }

    val allHabits: List<Habit> get() = routines.flatMap { it.habits } + unfiledHabits

    val allCompletions: List<Completion> get() = habits.flatMap { it.completions }

    fun habit(id: String?): Habit? = id?.let { wanted -> habits.firstOrNull { it.id == wanted } }

    companion object {
        val EMPTY = HabitsGraph(emptyList(), emptyList(), emptyList())

        /** Wires the relationships on freshly-loaded rows. Mutates the rows it is given. */
        fun assemble(
            routines: List<Routine>,
            habits: List<Habit>,
            completions: List<Completion>,
        ): HabitsGraph {
            val routineById = routines.associateBy { it.id }
            val habitById = habits.associateBy { it.id }

            habits.forEach {
                it.completions = mutableListOf()
                it.routine = it.routineId?.let(routineById::get)
            }
            routines.forEach { routine ->
                routine.habits = habits.filter { it.routineId == routine.id }
                    .sortedBy { it.sortIndex }
                    .toMutableList()
            }
            completions.forEach { completion ->
                completion.habit = habitById[completion.habitId]
                completion.habit?.completions?.add(completion)
            }

            return HabitsGraph(routines.sortedBy { it.sortIndex }, habits, completions)
        }
    }
}

/**
 * The write side of the store.
 *
 * Behind an interface so the mutation logic — the queue's merge rules, the reset receipt, the
 * one-per-day invariant — can be driven in a unit test without Room, a device or a wall clock.
 * `RoomHabitsStore` is the only implementation the app ships.
 */
interface HabitsStore {
    suspend fun routines(): List<Routine>
    suspend fun habits(): List<Habit>
    suspend fun completions(): List<Completion>

    suspend fun upsertRoutine(routine: Routine)
    suspend fun upsertHabit(habit: Habit)
    suspend fun deleteHabit(id: String)

    suspend fun insertCompletion(completion: Completion)
    suspend fun upsertCompletion(completion: Completion)
    suspend fun deleteCompletion(id: String)
    suspend fun reanchorCompletion(id: String, day: LocalDate)

    suspend fun loadGraph(): HabitsGraph = HabitsGraph.assemble(routines(), habits(), completions())

    fun observeGraph(): Flow<HabitsGraph>
}

class RoomHabitsStore(
    private val routineDao: RoutineDao,
    private val habitDao: HabitDao,
    private val completionDao: CompletionDao,
) : HabitsStore {
    override suspend fun routines(): List<Routine> = routineDao.all()
    override suspend fun habits(): List<Habit> = habitDao.all()
    override suspend fun completions(): List<Completion> = completionDao.all()

    override suspend fun upsertRoutine(routine: Routine) = routineDao.upsert(routine)
    override suspend fun upsertHabit(habit: Habit) = habitDao.upsert(habit)

    override suspend fun deleteHabit(id: String) {
        // Completions are declared CASCADE, but deleting them here too keeps a store without
        // foreign-key enforcement (a fresh in-memory test database) from leaking orphan rows.
        completionDao.all().filter { it.habitId == id }.forEach { completionDao.delete(it.id) }
        habitDao.delete(id)
    }

    override suspend fun insertCompletion(completion: Completion) = completionDao.insert(completion)
    override suspend fun upsertCompletion(completion: Completion) = completionDao.upsert(completion)
    override suspend fun deleteCompletion(id: String) = completionDao.delete(id)
    override suspend fun reanchorCompletion(id: String, day: LocalDate) = completionDao.reanchor(id, day.toEpochDay())

    override fun observeGraph(): Flow<HabitsGraph> =
        combine(routineDao.observeAll(), habitDao.observeAll(), completionDao.observeAll()) { r, h, c ->
            HabitsGraph.assemble(r, h, c)
        }

    companion object {
        fun from(database: HabitsDatabase): RoomHabitsStore =
            RoomHabitsStore(database.routines(), database.habits(), database.completions())
    }
}

/**
 * An in-memory store with the same contract. Used by the tests that exercise the mutation rules,
 * so those run in milliseconds and never touch a device clock.
 */
class InMemoryHabitsStore : HabitsStore {
    private val routineRows = mutableListOf<Routine>()
    private val habitRows = mutableListOf<Habit>()
    private val completionRows = mutableListOf<Completion>()

    override suspend fun routines(): List<Routine> = routineRows.sortedBy { it.sortIndex }
    override suspend fun habits(): List<Habit> = habitRows.sortedBy { it.sortIndex }
    override suspend fun completions(): List<Completion> = completionRows.toList()

    override suspend fun upsertRoutine(routine: Routine) {
        routineRows.removeAll { it.id == routine.id }
        routineRows.add(routine)
    }

    override suspend fun upsertHabit(habit: Habit) {
        habitRows.removeAll { it.id == habit.id }
        habitRows.add(habit)
    }

    override suspend fun deleteHabit(id: String) {
        habitRows.removeAll { it.id == id }
        completionRows.removeAll { it.habitId == id }
    }

    override suspend fun insertCompletion(completion: Completion) {
        completionRows.add(completion)
    }

    override suspend fun upsertCompletion(completion: Completion) {
        completionRows.removeAll { it.id == completion.id }
        completionRows.add(completion)
    }

    override suspend fun deleteCompletion(id: String) {
        completionRows.removeAll { it.id == id }
    }

    override suspend fun reanchorCompletion(id: String, day: LocalDate) {
        completionRows.firstOrNull { it.id == id }?.let {
            it.day = day
            it.legacyDayMillis = null
        }
    }

    override fun observeGraph(): Flow<HabitsGraph> = kotlinx.coroutines.flow.flow {
        emit(loadGraph())
    }
}
