# Habits$ — Android

A port of the iOS app to Kotlin + Jetpack Compose, at parity with the SwiftUI original. Same three
tabs, same derived-only stats, same terminal chrome.

```
./gradlew test          # the unit tests (no device, no network)
./gradlew assembleDebug # the APK
```

## What is here

| Layer | iOS | Android |
|---|---|---|
| Store | SwiftData `@Model` | Room `@Entity` + DAOs, wired by `HabitsGraph.assemble` |
| Preferences, widget snapshot, widget queue | `UserDefaults(suiteName:)` | `Storage` over `SharedPreferences` |
| Derived stats | `Streaks`, `Achievements`, `DayWindow` | the same, in `model/` |
| The day a completion belongs to | `Date.dayAnchor` (noon) + a DST-safe step walk | `HabitsClock.dayOf` over a configurable reset hour |
| Live timer | ActivityKit Live Activity | an ongoing notification with a chronometer |
| Reminders | `UNUserNotificationCenter` | `AlarmManager` one-off alarms |
| Widgets | WidgetKit (small, medium, lock screen) | Glance (4×2 and 2×2 home screen) |

Two rules from the PRD are load-bearing and are enforced in one place each:

* **Streaks are never stored.** Every number on the stats and achievements screens is computed from
  `Completion` rows on render. Un-checking a habit honestly un-earns what it paid for, because there
  is no second source of truth to drift.
* **A completion's day comes from `HabitsClock.dayOf` and nowhere else.** The reset hour is read
  through a lambda, so changing it in preferences takes effect everywhere at once without rebuilding
  the clock. Zero reproduces the iOS behaviour exactly.

## Layout

```
app/src/main/java/com/sahilchanna/habits/
  data/            entities, DAOs, the store seam, the repository, seed data
  model/           pure logic: streaks, achievements, day windows, snapshots, reminders
  notifications/   channels, the ongoing timer notification, alarm scheduling, receivers
  ui/              theme, shared components, the view model, one file per screen
  widgets/         the two Glance widgets
app/src/test/      unit tests, deterministic — no wall clock, no device, no Room
```

## Things worth knowing before reading the code

* **`HabitsStore` is the persistence seam.** `RoomHabitsStore` ships; `InMemoryHabitsStore` is what
  the tests drive. All mutation logic (the pending-toggle merge rules, the reset receipt, the
  one-per-day invariant) is exercised through it, so `./gradlew test` needs no device and no
  Robolectric.
* **A widget tap does not write to the database.** The widget can start the process on its own, so it
  records the desired state in the pending-toggle queue and mirrors it into the published snapshot;
  the app folds the queue in on its next publish. That is the same handshake as the iOS
  `ToggleHabitIntent`.
* **The ongoing timer notification is not a foreground service.** `setOngoing(true)` plus a
  chronometer satisfies the same need with none of the service-lifecycle risk, and the notification's
  own buttons go through the same pending-toggle queue as the widget.
* **Glance has no live timer.** A running habit in a widget shows the elapsed time at render, not a
  counting label; the widget is redrawn on every publish, so it is at worst one publish behind.
* **SF Symbol names are kept verbatim in storage.** They are the user's data and travel through the
  widget snapshot, so `ui/components/habitIcon` maps them to Material icons and falls back to the
  habit's first letter in monospace for a name it does not know.
