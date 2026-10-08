# Habits$ — terminal-styled habit tracker (iOS)

A daily habit tracker whose entire UI reads like a Unix shell session — prompts,
`//` comments, bracket checkboxes, monospace throughout. Built from
`~/Downloads/habit-tracker-prd.md` (MVP scope, PRD §10).

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

## What's in (MVP)

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
- **Live Activities** — running a timed habit posts an ActivityKit live
  activity: elapsed timer + progress on the Dynamic Island (device only —
  the island does not render live activities in the simulator) and the lock
  screen banner.
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
HabitsWidget/        widget extension: Dynamic Island + lock screen UI
```

## v2 (per PRD)

Achievements/XP/tiers, HealthKit sleep sync, Month/Week chart views,
home-screen widget, custom app icons, expanded theme store.