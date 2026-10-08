import AppIntents
import ActivityKit
import Foundation
import WidgetKit

// Live Activity buttons must use LiveActivityIntent, not AppIntent: the system runs a
// LiveActivityIntent in the *app's* process, whereas a plain AppIntent runs in the widget
// extension — which can't see the app's running activities and would silently no-op.

/// Set by the app at launch so an intent handled in the app's process can write straight
/// through to SwiftData instead of waiting for the next foreground publish.
enum TimerIntentHooks {
    static var applyPending: (() -> Void)?
}

/// Which process ran a button tap, and for which habit — `Bundle.main` tells app from
/// extension, which is exactly the thing that was wrong before.
func trace(_ message: String) {
    #if DEBUG
    HabitsDebugLog.append("intent: \(message)")
    #endif
}

/// The live activity's "log" button: records the completion, clears the running timer, and
/// ends the activity — without the app's UI coming forward.
struct LogTimerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Log timer"

    @Parameter(title: "habit") var habitId: String

    init() {}

    init(habitId: String) {
        self.habitId = habitId
    }

    func perform() async throws -> some IntentResult {
        trace("LogTimerIntent(\(habitId)) in \(Bundle.main.bundleIdentifier ?? "?")")
        guard let uuid = UUID(uuidString: habitId) else { return .result() }
        PendingToggleQueue.set(
            habitId: uuid,
            day: Calendar.current.startOfDay(for: Date()),
            done: true
        )
        // the widget's running line should go now, not when the app next opens
        HabitsSnapshot.applyToggle(habitId: uuid, done: true)
        HabitsSnapshot.clearRunning()
        await TimerActivityEnding.finish(done: true, habitId: habitId)
        // in the app's process we can settle it immediately; otherwise the next publish does
        TimerIntentHooks.applyPending?()
        TimerActivityEnding.reloadWidgets()
        return .result()
    }
}

/// "Discard": stops the timer without logging it.
struct DiscardTimerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Discard timer"

    @Parameter(title: "habit") var habitId: String

    init() {}

    init(habitId: String) {
        self.habitId = habitId
    }

    func perform() async throws -> some IntentResult {
        trace("DiscardTimerIntent(\(habitId)) in \(Bundle.main.bundleIdentifier ?? "?")")
        guard let uuid = UUID(uuidString: habitId) else { return .result() }
        PendingToggleQueue.stopTimer(habitId: uuid)
        HabitsSnapshot.clearRunning()
        await TimerActivityEnding.finish(done: false, habitId: habitId)
        TimerIntentHooks.applyPending?()
        TimerActivityEnding.reloadWidgets()
        return .result()
    }
}

/// "Pause"/"resume": stops the clock without ending the session — the activity stays up,
/// its countdown frozen where it stopped.
struct PauseTimerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause or resume timer"

    @Parameter(title: "habit") var habitId: String
    @Parameter(title: "paused") var paused: Bool

    init() {}

    init(habitId: String, paused: Bool) {
        self.habitId = habitId
        self.paused = paused
    }

    func perform() async throws -> some IntentResult {
        trace("PauseTimerIntent(\(habitId), paused: \(paused)) in \(Bundle.main.bundleIdentifier ?? "?")")
        guard let uuid = UUID(uuidString: habitId) else { return .result() }
        // Queue the change for SwiftData, and freeze the activity's own display now so the
        // lock screen reacts to the tap rather than to the next publish.
        PendingToggleQueue.setPaused(habitId: uuid, paused: paused)
        await TimerActivityEnding.setPaused(paused, habitId: habitId)
        TimerIntentHooks.applyPending?()
        TimerActivityEnding.reloadWidgets()
        return .result()
    }
}

/// Ends the timer activities belonging to one habit — not every activity, since several
/// timers can be running at once and each has its own.
enum TimerActivityEnding {
    /// `habitId` nil acts on all activities, which is only right for a full teardown.
    static func finish(done: Bool, habitId: String? = nil) async {
        let activities = Activity<TimerActivityAttributes>.activities.filter {
            habitId == nil || $0.attributes.habitId == habitId
        }
        trace("finish(done: \(done), habit: \(habitId ?? "all")) — \(activities.count) activity(ies)")
        // Let the dismissal policy below play out instead of being overridden by the
        // orphan sweep on the publish that follows.
        LiveActivityGrace.suppressSweep(
            for: done ? LiveActivityGrace.doneGrace : LiveActivityGrace.discardGrace)
        for activity in activities {
            var state = activity.content.state
            // Stamp the real time spent BEFORE clearing the pause state: a log tap while
            // paused must not bill the ongoing pause as work.
            let ongoingPause = state.pausedAt.map { max(0, Date().timeIntervalSince($0)) } ?? 0
            state.isDone = done
            state.pausedAt = nil
            if done {
                state.loggedSeconds = max(0, Date().timeIntervalSince(state.startDate) - state.pausedSeconds - ongoingPause)
            }
            await activity.end(
                ActivityContent(state: state, staleDate: nil),
                dismissalPolicy: done
                    ? .after(Date().addingTimeInterval(LiveActivityGrace.doneLinger))
                    : .immediate
            )
        }
    }

    static func reloadWidgets() {
        WidgetCenter.shared.reloadTimelines(ofKind: "TodayWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "LockWidget")
    }

    /// Freezes (or unfreezes) the countdown in place, without ending the session.
    static func setPaused(_ paused: Bool, habitId: String? = nil) async {
        let activities = Activity<TimerActivityAttributes>.activities.filter {
            habitId == nil || $0.attributes.habitId == habitId
        }
        for activity in activities {
            var state = activity.content.state
            guard (state.pausedAt != nil) != paused else { continue }
            if paused {
                state.pausedAt = Date()
            } else {
                // Fold the pause into the accumulated total so elapsed time stays honest.
                if let pausedAt = state.pausedAt {
                    state.pausedSeconds += max(0, Date().timeIntervalSince(pausedAt))
                }
                state.pausedAt = nil
            }
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }
}
