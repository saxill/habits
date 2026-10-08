# Habits$

A daily habit tracker whose entire interface reads like a Unix shell session —
prompts, `//` comments, bracket checkboxes, monospace throughout.

## Platforms

| | Path | Status |
|---|---|---|
| iOS | [`ios/`](ios/) | done — SwiftUI + SwiftData, iOS 17+, home-screen widget, Live Activities |
| Android | [`android/`](android/) | done — Kotlin + Jetpack Compose, Room, Glance widgets, ongoing-notification timer |

## Download

[Release v1.0](https://github.com/saxill/habits/releases/tag/v1.0) carries both
apps. `habits-android-debug.apk` is debug-signed and installs on any Android
phone. `Habits.ipa` is development-signed under Apple team `K75VPCXM64`, so it
installs **only on the single iPhone registered to that team**, and its
provisioning profile expires **2026-10-13** — after that it must be rebuilt to
launch. [`docs/install.md`](docs/install.md) has both routes and the from-source
build for each platform.

## What it does

- **Habits tab** — prompt header, rotating taglines, a Mon–Sun week strip with
  per-day completion fill, collapsible routines, per-habit rows with streak
  flames and completion timestamps.
- **Habit types** — check-off and timed. A timed habit shows a live
  `⏱ hh:mm:ss / target` counter; tapping starts and stops it and logs elapsed.
- **Stats tab** — today / streak / 30-day / total tiles, a five-week completion
  heatmap, and a per-habit deep dive over `7d/30d/90d/365d/all`.
- **Profile tab** — username, themes (ansi dark / dracula / solarized dark),
  prompt symbol, text sizes, and layout toggles with a live preview.

Streaks are always derived from completion history, never stored.

## Screenshots

| Habits | Stats | Profile |
|---|---|---|
| ![Habits tab](docs/screenshots/habits.png) | ![Stats tab](docs/screenshots/stats.png) | ![Profile tab](docs/screenshots/profile.png) |

## iOS

```bash
brew install xcodegen          # once
cd ios && xcodegen generate
open Habits.xcodeproj
```

Pick the Habits scheme and an iPhone simulator, then ⌘R. Requires Xcode 16+ /
iOS 17+. See [`ios/README.md`](ios/README.md) for device installs, the debug
driving hooks, and the module layout.

## Android

Kotlin + Jetpack Compose, Room, Glance widgets, and an ongoing notification with
a live chronometer in place of the Live Activity. At parity with the iOS build —
same three tabs, same derived-only stats, same terminal chrome.

```bash
cd android
./gradlew testDebugUnitTest   # the unit tests — no device, no network
./gradlew assembleDebug       # the APK
```

Requires JDK 17 and the Android SDK, its location set as `sdk.dir` in
`android/local.properties`. See [`android/README.md`](android/README.md) for the
module layout and the iOS→Android mapping.

## Documentation

[`docs/`](docs/README.md) indexes everything: the cross-platform
[architecture](docs/architecture.md) explainer, [install](docs/install.md)
instructions, and the two per-platform guides.
