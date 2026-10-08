# Habits$ documentation

Where to go for what. The root [`README.md`](../README.md) is the short product
overview; everything below is either a module-level guide or a cross-platform
explainer.

| Document | What it holds |
|---|---|
| [`../README.md`](../README.md) | What the app is, the tabs, the download links, and how to build each platform. |
| [`architecture.md`](architecture.md) | How the two apps are put together: the domain model, derived-only stats, the day boundary, the widget pipeline, timers, reminders, and the testing seams. Start here to understand the design. |
| [`install.md`](install.md) | Getting the app onto a phone: the signed release artifacts, and building from source on each platform. |
| [`../ios/README.md`](../ios/README.md) | iOS module layout, the xcodegen/Xcode run steps, and the debug driving hooks. |
| [`../android/README.md`](../android/README.md) | The module-by-module iOS→Android mapping table, the two load-bearing rules, and the Android source layout. |

## Screenshots

| Habits | Stats | Profile |
|---|---|---|
| ![Habits tab](screenshots/habits.png) | ![Stats tab](screenshots/stats.png) | ![Profile tab](screenshots/profile.png) |

All three are of the iOS build; the Android build renders the same three tabs
with the same terminal chrome.
