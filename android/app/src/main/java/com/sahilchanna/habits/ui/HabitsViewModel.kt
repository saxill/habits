package com.sahilchanna.habits.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.sahilchanna.habits.data.Habit
import com.sahilchanna.habits.data.HabitsGraph
import com.sahilchanna.habits.data.HabitsRepository
import com.sahilchanna.habits.data.HabitsShared
import com.sahilchanna.habits.data.Settings
import com.sahilchanna.habits.model.Achievements
import com.sahilchanna.habits.model.HabitsClock
import com.sahilchanna.habits.model.PendingToggleQueue
import com.sahilchanna.habits.model.StatsRange
import com.sahilchanna.habits.model.Streaks
import com.sahilchanna.habits.ui.theme.TerminalTheme
import com.sahilchanna.habits.ui.theme.ThemeStore
import com.sahilchanna.habits.ui.theme.fontScaleFor
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.util.UUID

/**
 * The screens' one source of state.
 *
 * Everything on screen is derived here from the store graph plus a handful of preferences, so a
 * mutation has exactly one path back to the UI: write, republish, and let the store's `Flow` deliver
 * the new graph. There is no second copy of the data for a screen to disagree with.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class HabitsViewModel(
    application: Application,
    val repo: HabitsRepository,
) : AndroidViewModel(application) {

    val settings: Settings get() = repo.settings
    val clock: HabitsClock get() = repo.clock
    private val themeStore = ThemeStore(settings)

    /** The live store. `flatMapLatest` so a database swap would re-subscribe cleanly. */
    private val graphFlow = MutableStateFlow(0).flatMapLatest { repo.observeGraph() }

    private val _graph = MutableStateFlow(HabitsGraph.EMPTY)
    val graph: StateFlow<HabitsGraph> = _graph.asStateFlow()

    private val _selectedDay = MutableStateFlow(clock.today())
    val selectedDay: StateFlow<LocalDate> = _selectedDay.asStateFlow()

    private val _statsRange = MutableStateFlow(StatsRange.D90)
    val statsRange: StateFlow<StatsRange> = _statsRange.asStateFlow()

    private val _habitRange = MutableStateFlow(StatsRange.D30)
    val habitRange: StateFlow<StatsRange> = _habitRange.asStateFlow()

    private val _theme = MutableStateFlow(themeStore.byId(settings.themeId))
    val theme: StateFlow<TerminalTheme> = _theme.asStateFlow()

    private val _username = MutableStateFlow(settings.username)
    val username: StateFlow<String> = _username.asStateFlow()

    private val _promptSymbol = MutableStateFlow(settings.promptSymbol)
    val promptSymbol: StateFlow<String> = _promptSymbol.asStateFlow()

    private val _fontScale = MutableStateFlow(fontScaleFor(settings.textSize))
    val fontScale: StateFlow<Float> = _fontScale.asStateFlow()

    private val _crossOut = MutableStateFlow(settings.crossOutCompleted)
    val crossOut: StateFlow<Boolean> = _crossOut.asStateFlow()

    private val _moveCompleted = MutableStateFlow(settings.moveCompletedToBottom)
    val moveCompleted: StateFlow<Boolean> = _moveCompleted.asStateFlow()

    private val _waterEnabled = MutableStateFlow(settings.waterRemindersEnabled)
    val waterEnabled: StateFlow<Boolean> = _waterEnabled.asStateFlow()

    private val _dayResetHour = MutableStateFlow(settings.dayResetHour)
    val dayResetHour: StateFlow<Int> = _dayResetHour.asStateFlow()

    private val _timerNotifications = MutableStateFlow(settings.timerNotificationsEnabled)
    val timerNotifications: StateFlow<Boolean> = _timerNotifications.asStateFlow()

    /**
     * A once-a-second pulse, collected only by the rows that show a live timer.
     *
     * A single shared tick rather than a coroutine per running habit: a screen can show several
     * timers at once, and each running its own second-timer is both wasteful and visibly out of
     * step with the others.
     */
    val ticker: StateFlow<Long> = MutableStateFlow(0L).also { flow ->
        viewModelScope.launch {
            while (true) {
                delay(1000)
                flow.value = System.currentTimeMillis()
            }
        }
    }.asStateFlow()

    /** The last reset, kept so the undo can be offered. Cleared when the window closes. */
    private val _undo = MutableStateFlow<List<com.sahilchanna.habits.model.DayReset.Dropped>>(emptyList())
    val undo: StateFlow<List<com.sahilchanna.habits.model.DayReset.Dropped>> = _undo.asStateFlow()

    private val queue = PendingToggleQueue(HabitsShared.storage(), HabitsShared.PENDING_TOGGLES_KEY)

    init {
        viewModelScope.launch {
            graphFlow.collect { incoming ->
                // The graph arrives from Room on a background thread with its relationships wired;
                // publishing it is what makes every derived number on screen recompute.
                _graph.value = incoming
            }
        }
        viewModelScope.launch {
            // A foreground is the only moment the queued widget taps can be folded in, and the
            // only moment the reminders can be re-armed against the state the user last saw.
            val current = repo.loadGraph()
            _graph.value = current
            repo.refresh(current)
        }
    }

    // MARK: - Derived

    fun habitsFor(day: LocalDate): List<Habit> = graph.value.allHabits.filter { it.scheduleDays.contains(Streaks.weekdayIndex(day)) }

    fun achievements(): Achievements.Snapshot =
        Achievements.Snapshot(graph.value.habits, clock.today(), clock)

    fun todayStreak(): Int = Streaks.overall(graph.value.allCompletions, clock.today())

    fun dayRatio(day: LocalDate): Double = Streaks.dayRatio(day, graph.value.habits, clock)

    val today: LocalDate get() = clock.today()

    // MARK: - Selection

    fun selectDay(day: LocalDate) {
        _selectedDay.value = day
    }

    fun selectStatsRange(range: StatsRange) {
        _statsRange.value = range
    }

    fun selectHabitRange(range: StatsRange) {
        _habitRange.value = range
    }

    // MARK: - Mutations

    fun toggle(habit: Habit) = launch { repo.toggle(habit, _selectedDay.value, graph.value) }

    fun logGlass(habit: Habit, count: Int = 1) = launch { repo.logGlass(habit, clock.today(), count, graph.value) }

    fun startTimer(habit: Habit) = launch { repo.startTimer(habit, graph.value) }

    fun togglePause(habit: Habit) = launch { repo.togglePause(habit, graph.value) }

    fun discardTimer(habit: Habit) = launch { repo.discardTimer(habit, graph.value) }

    fun saveHabit(habit: Habit) = launch { repo.saveHabit(habit, graph.value) }

    fun deleteHabit(habit: Habit) = launch { repo.deleteHabit(habit, graph.value) }

    /** Clears today and remembers the receipt, so the undo banner has something to put back. */
    fun resetToday() = launch {
        _undo.value = repo.reset(clock.today(), graph.value)
        // The offer expires with the day it belongs to: an undo that outlives the moment is a
        // trap rather than a favour.
        delay(UNDO_WINDOW_MS)
        _undo.value = emptyList()
    }

    fun undoReset() = launch {
        val dropped = _undo.value
        _undo.value = emptyList()
        repo.restore(dropped, graph.value)
    }

    fun dismissUndo() {
        _undo.value = emptyList()
    }

    // MARK: - Settings

    fun setUsername(value: String) {
        settings.username = value
        _username.value = settings.username
        launch { repo.publishOnly(graph.value) }
    }

    fun setPromptSymbol(value: String) {
        settings.promptSymbol = value.ifEmpty { "$" }
        _promptSymbol.value = settings.promptSymbol
    }

    fun setTextSize(tier: Int) {
        settings.textSize = tier
        _fontScale.value = fontScaleFor(settings.textSize)
    }

    fun setCrossOut(value: Boolean) {
        settings.crossOutCompleted = value
        _crossOut.value = value
    }

    fun setMoveCompleted(value: Boolean) {
        settings.moveCompletedToBottom = value
        _moveCompleted.value = value
    }

    fun setTheme(id: String) {
        settings.themeId = id
        _theme.value = themeStore.byId(id)
        launch { repo.publishOnly(graph.value) }
    }

    fun allThemes(): List<TerminalTheme> = themeStore.all

    fun upsertTheme(theme: TerminalTheme) {
        themeStore.upsert(theme)
        if (settings.themeId == theme.id) _theme.value = theme
    }

    fun deleteTheme(theme: TerminalTheme) {
        themeStore.delete(theme)
        if (settings.themeId == theme.id) setTheme(TerminalTheme.builtin().first().id)
    }

    fun newThemeId(): String = "custom-" + UUID.randomUUID().toString().take(8)

    fun setDayResetHour(hour: Int) {
        settings.dayResetHour = hour
        _dayResetHour.value = settings.dayResetHour
        // The day boundary moved, so "today" may have moved with it. Re-point the strip rather
        // than leaving the user looking at a day the app no longer considers current.
        _selectedDay.value = clock.today()
        launch { repo.refresh(graph.value) }
    }

    fun setWaterEnabled(value: Boolean) {
        settings.waterRemindersEnabled = value
        _waterEnabled.value = value
        launch { repo.onRemindersChanged(graph.value) }
    }

    fun setWaterWindow(start: Int, end: Int) {
        settings.waterStartHour = start
        settings.waterEndHour = end
        launch { repo.onRemindersChanged(graph.value) }
    }

    fun setWaterInterval(minutes: Int) {
        settings.waterIntervalMinutes = minutes
        launch { repo.onRemindersChanged(graph.value) }
    }

    fun setTimerNotifications(value: Boolean) {
        settings.timerNotificationsEnabled = value
        _timerNotifications.value = value
        launch { repo.refresh(graph.value) }
    }

    /**
     * Re-renders the ongoing notification after one of its display switches changed.
     *
     * The switches are read straight out of `settings` when the notification is built, so there is
     * no state here to update — but the notification on screen was built with the old values, and
     * only a publish reaches the code that rebuilds it.
     */
    fun refreshTimerNotification() = launch { repo.refresh(graph.value) }

    private fun launch(block: suspend () -> Unit) {
        viewModelScope.launch { block() }
    }

    companion object {
        const val UNDO_WINDOW_MS = 8000L
    }
}
