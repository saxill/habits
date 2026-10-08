import Foundation

/// App-group plumbing shared by the app and the widget extension.
/// The app publishes a compact "today" snapshot here; widgets render it.
enum HabitsShared {
    static let appGroup = "group.com.sahil.habits.term"
    static let snapshotKey = "habits.snapshot.v1"

    /// Shared defaults — nil when the app group isn't available (unsigned/preview).
    static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }
}

struct SnapshotHabit: Codable, Identifiable {
    var id: UUID
    var name: String
    var icon: String
    var colorHex: String
    var isTimed: Bool
    var done: Bool
    var streak: Int
}

struct SnapshotRoutine: Codable, Identifiable {
    var id: UUID
    var name: String
    var subtitle: String
    var icon: String
    var habits: [SnapshotHabit]
}

/// Everything the widgets need for one day — written by the app, read by the widget.
struct HabitsSnapshot: Codable {
    struct Running: Codable {
        var name: String
        var startedAt: Date
        var targetSeconds: Double
        var colorHex: String
        /// Non-nil while the timer is paused, so the widgets can say so too.
        var pausedAt: Date? = nil
        /// Seconds already lost to pauses.
        var pausedSeconds: TimeInterval = 0
    }

    var day: Date
    var generatedAt: Date
    var routines: [SnapshotRoutine]
    var doneCount: Int
    var totalCount: Int
    var streak: Int

    // active theme colors, so widgets match the in-app look
    var background: String
    var foreground: String
    var comment: String
    var accent: String

    var running: Running?

    /// Flattened habits for compact widget layouts.
    var flatHabits: [SnapshotHabit] { routines.flatMap { $0.habits } }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        HabitsShared.defaults?.set(data, forKey: HabitsShared.snapshotKey)
    }

    static func load() -> HabitsSnapshot? {
        guard let data = HabitsShared.defaults?.data(forKey: HabitsShared.snapshotKey) else { return nil }
        return try? JSONDecoder().decode(HabitsSnapshot.self, from: data)
    }

    /// Drops the running-timer line — used by the activity's own "log"/"discard" buttons,
    /// which end the timer without the app being open.
    static func clearRunning() {
        guard var snap = load(), snap.running != nil else { return }
        snap.running = nil
        snap.generatedAt = Date()
        snap.save()
    }

    /// Flips one habit in place, so an interactive-widget tap shows immediately instead of
    /// waiting for the app to come forward and republish. The app's next publish overwrites
    /// this with the authoritative store state.
    static func applyToggle(habitId: UUID, done: Bool) {
        guard var snap = load() else { return }
        var changed = false
        for r in snap.routines.indices {
            for h in snap.routines[r].habits.indices where snap.routines[r].habits[h].id == habitId {
                guard snap.routines[r].habits[h].done != done else { continue }
                snap.routines[r].habits[h].done = done
                snap.doneCount += done ? 1 : -1
                changed = true
            }
        }
        guard changed else { return }
        snap.doneCount = min(max(snap.doneCount, 0), snap.totalCount)
        snap.generatedAt = Date()
        snap.save()
    }

    /// Shown before the app has ever published (fresh install / widget gallery preview).
    static var placeholder: HabitsSnapshot {
        let sample = [
            SnapshotHabit(id: UUID(), name: "stretch", icon: "figure.flexibility", colorHex: "#00D7C3", isTimed: true, done: true, streak: 6),
            SnapshotHabit(id: UUID(), name: "drink water", icon: "drop", colorHex: "#5AA7FF", isTimed: false, done: true, streak: 11),
            SnapshotHabit(id: UUID(), name: "read", icon: "book", colorHex: "#C084FC", isTimed: false, done: false, streak: 4),
            SnapshotHabit(id: UUID(), name: "journal", icon: "square.and.pencil", colorHex: "#FFB454", isTimed: false, done: false, streak: 0),
        ]
        return HabitsSnapshot(
            day: Calendar.current.startOfDay(for: Date()),
            generatedAt: Date(),
            routines: [SnapshotRoutine(id: UUID(), name: "Morning", subtitle: "// after waking up",
                                       icon: "sun.max", habits: sample)],
            doneCount: 2, totalCount: 4, streak: 5,
            background: "#0A0A0D", foreground: "#E8E8E8", comment: "#6E6E73", accent: "#FFB454",
            running: nil
        )
    }
}
