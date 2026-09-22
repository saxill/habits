import ActivityKit
import Foundation

/// Shared between the app (starts/stops the activity) and the widget extension (renders it).
struct TimerActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// When the timer was (re)started — drives the auto-updating timer text.
        var startDate: Date
        var targetSeconds: TimeInterval
        var isDone: Bool
        /// Real timer time at the moment the habit was logged, pauses excluded. Set when
        /// the activity is ended as done, so the completion card reports what was actually
        /// spent rather than the target it was aiming at.
        var loggedSeconds: TimeInterval? = nil
        /// Non-nil while paused. The countdown can't be frozen in place (a timer interval
        /// keeps ticking), so the view swaps to a static remaining time while this is set.
        var pausedAt: Date? = nil
        /// Seconds already lost to pauses, so a resume doesn't count them as elapsed.
        var pausedSeconds: TimeInterval = 0
        // display prefs (what to show), captured at activity start
        var showTimer: Bool = true
        var showProgress: Bool = true
        var showName: Bool = true
        /// Count down to the target instead of counting elapsed time up.
        var countDown: Bool = true
        // Display fields, duplicated into state so the app can refresh them on every publish:
        // `attributes` are immutable for the activity's life, so renaming, recoloring or
        // re-routing a habit mid-timer would otherwise keep showing the values captured at
        // start. Optional so activities started by an older build still decode.
        var liveName: String? = nil
        var liveIcon: String? = nil
        var liveColorHex: String? = nil
        var liveRoutineName: String? = nil
        // today's context, refreshed by the app on every snapshot publish
        var doneToday: Int = 0
        var totalToday: Int = 0
        var streak: Int = 0
    }

    var habitName: String
    /// SF Symbol name, so the island shows the habit's own glyph.
    var habitIcon: String
    /// Hex string like "00D7C3"; the extension re-parses it since Color Codable differs across targets.
    var colorHex: String
    /// Lets the activity's own buttons log or discard the timer without the app.
    var habitId: String
    /// Shown on the completion card as `// routine: Deep Work`.
    var routineName: String = ""
}
