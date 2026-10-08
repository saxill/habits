# Habits$ — terminal-styled habit tracker (iOS)

A daily habit tracker whose entire UI reads like a Unix shell session — prompts,
`//` comments, bracket checkboxes, monospace throughout. Built from
`~/Downloads/habit-tracker-prd.md`.

## Run it

```bash
brew install xcodegen          # once
cd ~/projects/HabitsTerm/ios
xcodegen generate
open Habits.xcodeproj          # pick the Habits scheme + an iPhone sim, Cmd+R
```

Or headless:

```bash
xcodebuild -project Habits.xcodeproj -scheme Habits \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath ./build build
xcrun simctl install booted ./build/Build/Products/Debug-iphonesimulator/Habits.app
xcrun simctl launch booted com.sahil.habits.term
```

## What's in

- **Habits tab** — prompt header, rotating `//` tagline, date row, overall streak
  (🔥 / 🛡 freeze tokens), Mon–Sun week strip with per-day completion fill,
  collapsible routines, per-habit rows with color coding, streak flames,
  completion timestamps.
- **Habit types** — check-off + timed. Timed habits show a live
  `⏱ hh:mm:ss / target` counter; tapping starts/stops and logs elapsed.
- **Stats tab** — overview (today/streak/30d/total tiles + 5-week completion
  heatmap) and per-habit deep dive (mode, streak, best, tracked, completions
  rate over `7d/30d/90d/365d/all`).
- **Profile tab** — username (15-char counter), 3 themes (ansi dark / dracula /
  solarized dark) with ANSI swatch dots, prompt symbol, 3 text sizes,
  cross-out + move-completed-to-bottom toggles, live preview row.
- **Achievements** — a tier ladder per metric (completions, goal days,
  dedication, routine runs) with XP and milestones, pushed from the Profile tab.
  Every number is derived from completion history, so un-checking honestly
  un-earns what it paid for.
- **Live Activities** — running a timed habit posts an ActivityKit live
  activity: elapsed timer + progress on the Dynamic Island (device only —
  the island does not render live activities in the simulator) and the lock
  screen banner.
- **Water reminders** — a `glass of water` habit keeps a glass tally in the
  completion's `value` alongside its own reminder window, so the count moves
  without a day ever having two completions.
- **Home-screen and lock-screen widgets** — `TodayWidget` and `LockWidget` in
  `HabitsWidget/`, fed from the published snapshot. A widget tap can't reach the
  database (it can start the process on its own), so it records the intent and
  the app folds it in on the next publish.
- **Custom themes** — the three built-ins plus a `ThemeEditorView` sheet to edit
  and keep your own.
- First launch seeds 3 routines / 7 habits / 9 days of history so everything
  is alive immediately. Streaks are derived from completion history, never
  stored (PRD §7).

## Debug driving hooks (DEBUG builds only)

Launch-environment variables via `SIMCTL_CHILD_*`:

```bash
SIMCTL_CHILD_DEBUG_AUTO_TIMER=1 xcrun simctl launch booted com.sahil.habits.term  # start first timed habit
SIMCTL_CHILD_DEBUG_TAB=stats   xcrun simctl launch booted com.sahil.habits.term
SIMCTL_CHILD_DEBUG_TAB=profile xcrun simctl launch booted com.sahil.habits.term
```

## Layout

```
project.yml          xcodegen spec (app + widget extension)
Shared/              TimerActivityAttributes (app ↔ widget)
Habits/              app target: models, streaks, theme, views
HabitsWidget/        widget extension: today's habits, lock screen, Dynamic Island
```

## Still to come (per PRD)

HealthKit sleep sync, Month/Week chart views, custom app icons.