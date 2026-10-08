import AppIntents
import Foundation
import WidgetKit

/// Runs inside the widget extension when a habit row is tapped. It flips the row in the
/// shared snapshot right away — so the widget shows the check without launching the app —
/// and queues the change for the app to persist into SwiftData.
struct ToggleHabitIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle habit"

    @Parameter(title: "habit") var habitId: String
    @Parameter(title: "day") var day: Date
    @Parameter(title: "done") var done: Bool

    init() {}

    init(habitId: UUID, day: Date, done: Bool) {
        self.habitId = habitId.uuidString
        self.day = day
        self.done = done
    }

    func perform() async throws -> some IntentResult {
        trace("ToggleHabitIntent(\(habitId)) done=\(done) in \(Bundle.main.bundleIdentifier ?? "?")")
        guard let uuid = UUID(uuidString: habitId) else { return .result() }
        PendingToggleQueue.set(habitId: uuid, day: day, done: done)
        HabitsSnapshot.applyToggle(habitId: uuid, done: done)
        WidgetCenter.shared.reloadTimelines(ofKind: "TodayWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "LockWidget")
        return .result()
    }
}
