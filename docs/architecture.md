# Architecture

Habits$ is one domain model with two native front ends. Nothing about habits,
completions, streak math or the day boundary is duplicated as *data* between them
— the two stores hold the same three entities and answer the same questions from
the same rules. This page is the cross-platform view; the module-by-module
mapping table lives in [`../android/README.md`](../android/README.md).

## The domain model

Three entities: a `Routine` groups `Habit`s, and a `Completion` is one habit done
on one day.

**iOS** — [`ios/Habits/Models.swift`](../ios/Habits/Models.swift). SwiftData
`@Model` classes. The relationships are declared on the models:
`@Relationship(inverse: \Completion.habit) var completions` on `Habit`, and a
plain `var routine: Routine?`. SwiftData hydrates them; the same object instance
is what the routine, the completions and the view all see.

**Android** — [`data/Entities.kt`](../android/app/src/main/java/com/sahilchanna/habits/data/Entities.kt),
[`data/Daos.kt`](../android/app/src/main/java/com/sahilchanna/habits/data/Daos.kt),
[`data/HabitsDatabase.kt`](../android/app/src/main/java/com/sahilchanna/habits/data/HabitsDatabase.kt).
Room `@Entity` classes with the same fields. `Completion.habitId` carries a
foreign key with `onDelete = CASCADE` and `Habit.routineId` one with
`SET_NULL`. Room hydrates columns but **not** relationships, so the entity carries
`@Ignore var completions` / `@Ignore var routine`, and
`HabitsGraph.assemble` in
[`data/HabitsStore.kt`](../android/app/src/main/java/com/sahilchanna/habits/data/HabitsStore.kt)
wires them after every load — the same one-instance-per-habit shape SwiftData
gives iOS for free.

Fields worth naming on both sides, because they are stored as raw strings that
travel through the widget snapshot unchanged: `typeRaw` (`checkbox` / `timed`),
`colorRaw` (a colour raw value), `scheduleRaw` (a comma-joined weekday list,
1 = Sun … 7 = Sat), and `reminderMinutesFromMidnight`. A running timer is
`startedAt` + `pausedAt` + `pausedSeconds`, so a pause is exact and the elapsed
seconds are `(now - started) - pausedSeconds`, pauses excluded.

The **day a completion belongs to** is the one field the two stores hold
differently, and the next section is why.

## Derived state is never stored

No entity or model in either app has a streak, tier, XP or goal-day column. Those
numbers exist only as functions over completion rows, evaluated on render:

| Concept | Android | iOS |
|---|---|---|
| Streaks | [`model/Streaks.kt`](../android/app/src/main/java/com/sahilchanna/habits/model/Streaks.kt) — `habitStreak`, `overall`, `bestStreak`, `bestOverall`, `dayRatio` | [`Habits/Streaks.swift`](../ios/Habits/Streaks.swift) — the same five |
| Achievements, tiers, XP | [`model/Achievements.kt`](../android/app/src/main/java/com/sahilchanna/habits/model/Achievements.kt) — the `sh → bash → zsh → sudo → root` ladder, four metrics, per-tier XP rewards | [`Habits/Achievements.swift`](../ios/Habits/Achievements.swift) — the same ladder and metrics |
| Goal days, completion rate | `HabitDays.tally` in [`model/DayWindow.kt`](../android/app/src/main/java/com/sahilchanna/habits/model/DayWindow.kt) | `DayWindow` / the stats view |

What this buys: un-checking a habit deletes its `Completion` row and every number
falls with it, honestly — there is no cached streak to go stale and no second
source of truth to drift. The achievements feature needed no schema change and no
backfill: an existing install lights up from the history it already has.

Two rules that fall out of it and are enforced in one place each:

- **One completion per habit per day.** `Habit.completion(day)` is a
  first-match lookup on both sides, `HabitsRepository.complete` refuses to insert
  a second row for a day
  ([`data/HabitsRepository.kt`](../android/app/src/main/java/com/sahilchanna/habits/data/HabitsRepository.kt)),
  and `DayReset.restore` refuses to reinsert if a newer completion exists
  ([`model/DayReset.kt`](../android/app/src/main/java/com/sahilchanna/habits/model/DayReset.kt)).
- **Past days can be corrected, never completed.** A tick is stamped with the
  moment it was made, so one placed on yesterday would read as "done that day"
  while being a lie. The habit row enforces this in-app (`HabitsRepository.toggle`)
  and the widget path enforces it again (`PendingToggleApplier`), because a tap
  can arrive after midnight for the previous day's reminder.

## The day boundary

This is the problem the two platforms answer differently.

**iOS stores a day as a `Date` anchored at noon.** `Date.dayAnchor` in
[`ios/Habits/Models.swift`](../ios/Habits/Models.swift) is applied to every
completion's `day` on construction, and every read goes through `startOfDay` /
`isDate(inSameDayAs:)`. A midnight anchor moves when the device's zone moves:
complete a habit, fly a few time zones, and the stored midnight can read as the
neighbouring day back home. Noon survives any offset a zone is likely to move by.
Rows written before 2026-09-28 carry a midnight anchor, and
[`Habits/CompletionDayAnchor.swift`](../ios/Habits/CompletionDayAnchor.swift)
re-anchors them once, guarded by `SettingsKey.completionDaysAnchored`. The same
file documents the honest caveat: a row written in one zone and migrated in
another shifts by the zone change.

The iOS streak walk needs a second guard. `Streaks.step` re-normalises every step
to midnight, because `date(byAdding: .day)` from a midnight lands outside the day
it should name in zones whose DST transition happens exactly at midnight (Chile,
Egypt, Cuba) — the cursor drifts off the grid of day-starts the `done` set is
built from and the walk stops early or never ends.

**Android stores a day as a calendar date.** `Completion.dayEpochDay` is a
`LocalDate` epoch day, exposed as `day: LocalDate`; `Completion.of` is the only
construction path, so no caller can forget to derive it
([`data/Entities.kt`](../android/app/src/main/java/com/sahilchanna/habits/data/Entities.kt)).
A calendar date has neither of the iOS problems, so the walk is a plain
`plusDays`.

Android also adds the one genuinely new feature of the port: a configurable
**day-reset hour**. `HabitsClock.dayOf` in
[`model/HabitsClock.kt`](../android/app/src/main/java/com/sahilchanna/habits/model/HabitsClock.kt)
subtracts the reset hour from the instant and takes the zoned local date, so a
night-owl who logs at 01:00 can set the boundary to 04:00 and have that session
still count as the previous day. Zero — the default — reproduces the iOS
behaviour exactly. The hour is read through a `() -> Int` lambda wired from
preferences in `HabitsRuntime.clock`, so changing it in the profile screen takes
effect everywhere at once without rebuilding the clock.

Android still carries a migration for the same legacy rows, because a store can
arrive from an older build or an iOS backup: `Completion.legacyDayMillis` is
non-null only on those rows, and
[`model/CompletionDayAnchor.kt`](../android/app/src/main/java/com/sahilchanna/habits/model/CompletionDayAnchor.kt)
folds them into a calendar day once.

## The widget pipeline

Both apps publish a compact "today" snapshot into shared storage and render the
widget from that, never from the database.

**Publish.** iOS: `SnapshotPublisher.publish` in
[`Habits/SnapshotPublisher.swift`](../ios/Habits/SnapshotPublisher.swift) fetches
the routines and habits, builds a `HabitsSnapshot`, saves it as JSON into the app
group's `UserDefaults` (suite `group.com.sahil.habits.term`, key
`habits.snapshot.v1`, both in
[`Shared/HabitsSnapshot.swift`](../ios/Shared/HabitsSnapshot.swift)), then calls
`WidgetCenter.shared.reloadAllTimelines()`. Android:
[`data/SnapshotPublisher.kt`](../android/app/src/main/java/com/sahilchanna/habits/data/SnapshotPublisher.kt)
builds the same object via `SnapshotBuilder` and `Snapshots.save` into
SharedPreferences (key `habits.snapshot.v2`, in
[`data/Storage.kt`](../android/app/src/main/java/com/sahilchanna/habits/data/Storage.kt));
the redraw is `TodayWidget().updateAll(...)` from
[`notifications/SideEffects.kt`](../android/app/src/main/java/com/sahilchanna/habits/notifications/SideEffects.kt).

The snapshot carries the routines and the habits **scheduled today** (a Mon/Wed/Fri
habit does not sit unticked in a Sunday widget), a `doneCount` / `totalCount`, the
overall streak, the active theme's four colours, and at most one `running` line —
the most recently started timer, since the widget has room for one. Unfiled habits
get a synthetic `unfiled` routine so they do not vanish from a widget while still
counting in stats.

**A widget tap never writes to the database.** iOS: `ToggleHabitIntent` in
[`Shared/ToggleHabitIntent.swift`](../ios/Shared/ToggleHabitIntent.swift) is an
`AppIntent` that runs inside the widget extension. It records the desired state in
the pending-toggle queue
([`Shared/PendingToggles.swift`](../ios/Shared/PendingToggles.swift), key
`habits.pendingToggles.v1`) and flips the row in the shared snapshot in place
(`HabitsSnapshot.applyToggle`) so the check appears without launching the app.
Android: `ToggleHabitAction` in
[`widgets/TodayWidget.kt`](../android/app/src/main/java/com/sahilchanna/habits/widgets/TodayWidget.kt)
does the same two writes through
[`model/PendingToggles.kt`](../android/app/src/main/java/com/sahilchanna/habits/model/PendingToggles.kt)
and `Snapshots.applyToggle`.

**The app folds the queue in before every publish.** `PendingToggleApplier` — iOS
[`Habits/PendingToggleApplier.swift`](../ios/Habits/PendingToggleApplier.swift),
Android
[`model/PendingToggleApplier.kt`](../android/app/src/main/java/com/sahilchanna/habits/model/PendingToggleApplier.kt)
— drains the queue at the start of `publish`, so the snapshot and the UI both
reflect the tap, and the next authoritative publish overwrites the in-place edit.

The merge rules on enqueue are the subtle part, and are identical on both sides:
`stopTimer` ("discard") supersedes everything queued; `pause` touches only the
pause flag and leaves `done` and `glasses` alone; `glasses` accumulates (two
taps are two glasses, and the first still ticks the day); a plain `done` replaces
the done-state, because it is a state rather than a quantity. Merging rather than
replacing is what stops a widget tick from vanishing under the next
live-activity pause.

Why it is built this way: the widget (and the iOS extension) can start the process
on its own, before the app has any repository, and must not open the database on
the home-screen render path — a slow query there is a frozen home screen. The
queue makes the tap durable and immediately visible, and the app is the only
process that owns the database.

The same queue is used by every out-of-app action: iOS reminder actions in
[`Habits/NotificationRouter.swift`](../ios/Habits/NotificationRouter.swift) and
the live-activity buttons; Android reminder and timer actions in
[`notifications/Receivers.kt`](../android/app/src/main/java/com/sahilchanna/habits/notifications/Receivers.kt).
A notification action and a tap in the app are therefore one code path, which is
what keeps them from disagreeing about whether something was logged.

## Timed habits

**iOS — ActivityKit.** `LiveActivityController` in
[`Habits/LiveActivityController.swift`](../ios/Habits/LiveActivityController.swift)
requests one `Activity<TimerActivityAttributes>`
([`Shared/TimerActivityAttributes.swift`](../ios/Shared/TimerActivityAttributes.swift))
per running habit and renders it on the Dynamic Island and lock screen in
[`HabitsWidget/HabitsWidget.swift`](../ios/HabitsWidget/HabitsWidget.swift). It is
keyed by habit rather than holding one handle: N running timers means N
activities, so starting a second timer cannot silently end the first. The buttons
are `LiveActivityIntent`s, not plain `AppIntent`s
([`Shared/TimerIntents.swift`](../ios/Shared/TimerIntents.swift)) — the system
runs a `LiveActivityIntent` in the *app's* process, whereas a plain `AppIntent`
runs in the extension, which cannot see the app's activities and would no-op.
`TimerIntentHooks.applyPending` lets such a tap write straight through to the
store. [`Shared/LiveActivityGrace.swift`](../ios/Shared/LiveActivityGrace.swift)
suppresses the orphan sweep briefly after a deliberate end, so a finished timer's
completion card is not eaten by the publish that follows.

**Android — an ongoing notification with a chronometer.**
[`notifications/TimerNotifications.kt`](../android/app/src/main/java/com/sahilchanna/habits/notifications/TimerNotifications.kt)
posts an ongoing, non-dismissible notification whose live timer is the *system's*,
set with `setUsesChronometer(true)` and a base instant rather than by the app
pushing text every second. That is what keeps it ticking correctly while the app is
not running. It has three actions — pause/resume, done, discard — wired through
the pending-toggle queue via `TimerActionReceiver`.

The notification is deliberately **not a foreground service**. `setOngoing(true)`
plus the system chronometer satisfies the same need — a live, non-dismissible
status line that survives the app being killed — with none of the
service-lifecycle obligations and their failure modes. The display switches
(show the timer, show `3/7` progress, show the habit name, count down) are
Android-only preferences in
[`model/SettingsKey.kt`](../android/app/src/main/java/com/sahilchanna/habits/model/SettingsKey.kt),
replacing iOS's live-activity switches. Glance has no live timer, so a running
habit in a widget shows the elapsed time *at render*, not a counting label — the
widget is redrawn on every publish, so it is at worst one publish behind.

## Reminders

**iOS — `UNUserNotificationCenter`.**
[`Habits/HabitReminders.swift`](../ios/Habits/HabitReminders.swift) schedules
one-off `UNCalendarNotificationTrigger`s (`repeats: false`) across a 7-day
lookahead, truncated to fit iOS's 64-pending-notification cap (minus a reserve,
minus what the water reminders took). Water nudges are
[`Habits/WaterReminders.swift`](../ios/Habits/WaterReminders.swift) over a 2-day
window. Lock-screen actions are routed in `NotificationRouter`.

**Android — `AlarmManager`.**
[`notifications/ReminderScheduler.kt`](../android/app/src/main/java/com/sahilchanna/habits/notifications/ReminderScheduler.kt)
arms `setExactAndAllowWhileIdle` alarms (falling back to an inexact alarm when the
exact-alarm permission is not held, so something still arrives). The arithmetic
lives in [`model/Reminders.kt`](../android/app/src/main/java/com/sahilchanna/habits/model/Reminders.kt):
`LOOKAHEAD_DAYS = 7` for habits, a 2-day window for water. `ReminderBootReceiver`
re-arms after a reboot, since the system drops alarms with it.

The lookahead window exists to solve one specific defect: a *repeating* weekly
trigger cannot be withdrawn for a single day, so a reminder for a habit already
ticked off still buzzes, and the OS offers no way to skip just today's occurrence.
A rolling window of concrete dated occurrences can be filtered at sync time —
"remind me at 08:00" goes quiet on a morning the habit is done — and a fired
reminder can quote today's streak and today's glass count rather than the values
frozen in when the schedule was built. The whole window is re-armed whenever the
app comes forward or the store changes.

Re-arming on every publish would be wasteful, since every checkbox tap publishes.
Android's `RemindersSideEffects` therefore re-arms only when a fingerprint of the
scheduled occurrences changes.

## Testing

**Android** runs 118 JUnit4 tests in
[`android/app/src/test`](../android/app/src/test/java/com/sahilchanna/habits) —
ten files covering streaks, achievements and XP, the stats windows and their
denominators, the clock and its reset hour, the pending-toggle merge and apply
rules, the reminder arithmetic, the snapshot's in-place edits, the day reset, and
the demo-history sweep. They need no device, no Robolectric and no wall clock:
[`T.kt`](../android/app/src/test/java/com/sahilchanna/habits/T.kt) pins a
`Clock.fixed` in UTC, because half the logic under test is *about* which day
something belongs to.

That is possible because persistence is a seam. `HabitsStore` in
[`data/HabitsStore.kt`](../android/app/src/main/java/com/sahilchanna/habits/data/HabitsStore.kt)
is an interface; `RoomHabitsStore` is the only implementation the app ships, and
`InMemoryHabitsStore` is what the tests drive. Preferences are behind `Storage`
with a `MemoryStorage`. The mutation logic — the queue's merge rules, the reset
receipt, the one-per-day invariant — is all exercised through those two
interfaces.

**iOS** has XCTest unit tests in
[`ios/HabitsTests`](../ios/HabitsTests) against an in-memory `ModelContainer`
(`ReminderScheduleTests`, `AuditFixTests`, `DayResetTests`, `DemoHistoryTests`),
plus UI tests in [`ios/HabitsUITests`](../ios/HabitsUITests) that drive real
gestures. The swipe and drag interactions cannot be injected by `simctl` or
`devicectl`, so the UI-test target is the only way to exercise them at all.
