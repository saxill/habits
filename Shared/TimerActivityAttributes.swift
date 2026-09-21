import ActivityKit
import Foundation

/// Shared between the app (starts/stops the activity) and the widget extension (renders it).
struct TimerActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// When the timer was (re)started — drives the auto-updating elapsed text.
        var startDate: Date
        var targetSeconds: TimeInterval
        var isDone: Bool
    }

    var habitName: String
    var emoji: String
    /// Hex string like "00D7C3"; the extension re-parses it since Color Codable differs across targets.
    var colorHex: String
}