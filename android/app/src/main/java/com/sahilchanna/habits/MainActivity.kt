package com.sahilchanna.habits

import android.Manifest
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.HorizontalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sahilchanna.habits.data.Habit
import com.sahilchanna.habits.ui.HabitsViewModel
import com.sahilchanna.habits.ui.components.MutedGrey
import com.sahilchanna.habits.ui.components.TermText
import com.sahilchanna.habits.ui.screens.AchievementsScreen
import com.sahilchanna.habits.ui.screens.AddHabitScreen
import com.sahilchanna.habits.ui.screens.HabitsScreen
import com.sahilchanna.habits.ui.screens.ProfileScreen
import com.sahilchanna.habits.ui.screens.StatsScreen
import com.sahilchanna.habits.ui.theme.LocalFontScale
import com.sahilchanna.habits.ui.theme.LocalTerminalTheme
import kotlinx.coroutines.launch

/**
 * The single activity.
 *
 * Everything is Compose below it — there is no second activity and no fragments, because the whole
 * app is three tabs and two pushed screens, and a navigation library would be more moving parts
 * than the navigation.
 */
class MainActivity : ComponentActivity() {

    /**
     * Android 13 and up require a runtime grant before any notification can be posted — including
     * the ongoing timer one, which is the app's substitute for a Live Activity. Asking on first
     * launch rather than when a timer starts, because the permission dialog would otherwise appear
     * over a running timer the user is watching.
     */
    private val requestNotifications = registerForActivityResult(ActivityResultContracts.RequestPermission()) { }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            requestNotifications.launch(Manifest.permission.POST_NOTIFICATIONS)
        }

        setContent {
            val factory = remember {
                object : ViewModelProvider.Factory {
                    @Suppress("UNCHECKED_CAST")
                    override fun <T : androidx.lifecycle.ViewModel> create(modelClass: Class<T>): T =
                        HabitsViewModel(application, HabitsRuntime.repository(this@MainActivity)) as T
                }
            }
            val viewModel: HabitsViewModel = viewModel(factory = factory)
            HabitsRoot(viewModel)
        }
    }

    override fun onStop() {
        super.onStop()
        // Leaving the app is the last chance to leave the widget with the true picture — and to
        // fold in anything a widget queued while the app was in the background.
        lifecycleScope.launch {
            runCatching { HabitsRuntime.repository(this@MainActivity).refresh(HabitsRuntime.store(this@MainActivity).loadGraph()) }
        }
    }
}

/** The three tabs and the two pushed screens. */
private sealed interface Screen {
    data object Tabs : Screen
    data class EditHabit(val habit: Habit?) : Screen
    data object Achievements : Screen
}

@Composable
private fun HabitsRoot(viewModel: HabitsViewModel) {
    val theme by viewModel.theme.collectAsState()
    val fontScale by viewModel.fontScale.collectAsState()

    var tab by remember { mutableStateOf(0) }
    var screen by remember { mutableStateOf<Screen>(Screen.Tabs) }

    CompositionLocalProvider(
        LocalTerminalTheme provides theme,
        LocalFontScale provides fontScale,
    ) {
        Box(Modifier.fillMaxSize().background(theme.bg)) {
            when (val current = screen) {
                is Screen.Tabs -> Column(Modifier.fillMaxSize()) {
                    Box(Modifier.weight(1f)) {
                        when (tab) {
                            0 -> HabitsScreen(
                                viewModel = viewModel,
                                onAddHabit = { screen = Screen.EditHabit(null) },
                                onEditHabit = { screen = Screen.EditHabit(it) },
                            )
                            1 -> StatsScreen(viewModel)
                            else -> ProfileScreen(
                                viewModel = viewModel,
                                onOpenAchievements = { screen = Screen.Achievements },
                            )
                        }
                    }
                    TabBar(selected = tab, onSelect = { tab = it })
                }

                is Screen.EditHabit -> AddHabitScreen(
                    viewModel = viewModel,
                    existing = current.habit,
                    onDone = { screen = Screen.Tabs },
                )

                is Screen.Achievements -> AchievementsScreen(
                    viewModel = viewModel,
                    onBack = { screen = Screen.Tabs },
                )
            }
        }
    }
}

/**
 * The tab bar.
 *
 * Terminal text rather than a Material navigation bar: three items on a phone get a Material
 * treatment that centers icons under captions, which reads nothing like the rest of the app. The
 * selected tab is bracketed, which is the same convention the checkboxes use.
 */
@Composable
private fun TabBar(selected: Int, onSelect: (Int) -> Unit) {
    val theme = LocalTerminalTheme.current
    val tabs = listOf("habits", "stats", "profile")
    Column {
        HorizontalDivider(color = theme.commentColor.copy(alpha = 0.4f))
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(theme.bg)
                .padding(horizontal = 16.dp, vertical = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            tabs.forEachIndexed { index, label ->
                val isSelected = index == selected
                TermText(
                    text = if (isSelected) "[$label]" else " $label ",
                    size = 13f,
                    weight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal,
                    color = if (isSelected) theme.habitsColor else MutedGrey,
                    modifier = Modifier.clickable { onSelect(index) },
                )
            }
            Spacer(Modifier.weight(1f))
        }
    }
}
