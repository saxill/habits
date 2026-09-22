import Foundation

/// A state change made from an interactive widget, waiting for the app to fold it into
/// SwiftData. The widget extension can't open the app's store, so it records the desired
/// state here; the app applies it before its next snapshot publish.
struct PendingToggle: Codable {
    var habitId: UUID
    var day: Date
    var done: Bool
    var at: Date
    /// Set by the live activity's "discard": stop the running timer, log nothing.
    var stopTimer: Bool = false
    /// Set by the live activity's pause/resume key: the desired paused state. Optional so
    /// entries queued by an older build still decode.
    var pause: Bool? = nil
    /// Set by "log glass": how many glasses to *add* to the day. Water is the one habit measured
    /// in a count rather than a tick, so its completion's `value` is a glass tally — and logging
    /// a glass is an increment, not a state, which is why it cannot go through `done` (that
    /// no-ops once the day is ticked off).
    var glasses: Int? = nil
}

enum PendingToggleQueue {
    private static let key = "habits.pendingToggles.v1"

    static func load() -> [PendingToggle] {
        guard let data = HabitsShared.defaults?.data(forKey: key),
              let list = try? JSONDecoder().decode([PendingToggle].self, from: data)
        else { return [] }
        return list
    }

    /// Logs one (or more) glasses of water against the habit's day.
    static func logGlass(habitId: UUID, day: Date, count: Int = 1) {
        enqueue(PendingToggle(
            habitId: habitId,
            day: day,
            done: true,
            at: Date(),
            glasses: count
        ))
    }

    /// Records the desired state for one habit/day. Tapping twice replaces the entry
    /// rather than queueing a second toggle, so the result is always what's on screen.
    static func set(habitId: UUID, day: Date, done: Bool) {
        enqueue(PendingToggle(habitId: habitId, day: day, done: done, at: Date()))
    }

    /// Stops a running timer without logging it.
    static func stopTimer(habitId: UUID) {
        enqueue(PendingToggle(
            habitId: habitId,
            day: Calendar.current.startOfDay(for: Date()),
            done: false,
            at: Date(),
            stopTimer: true
        ))
    }

    /// Pauses or resumes a running timer without logging it.
    static func setPaused(habitId: UUID, paused: Bool) {
        enqueue(PendingToggle(
            habitId: habitId,
            day: Calendar.current.startOfDay(for: Date()),
            done: false,
            at: Date(),
            pause: paused
        ))
    }

    private static func enqueue(_ entry: PendingToggle) {
        let cal = Calendar.current
        var list = load()
        if let i = list.firstIndex(where: {
            $0.habitId == entry.habitId && cal.isDate($0.day, inSameDayAs: entry.day)
        }) {
            // Glasses *accumulate*, unlike every other field here. Replacing would mean two
            // "log glass" taps landing before the app applies them counted as one glass — the
            // exact kind of silent undercount this change exists to remove. Anything else
            // replaces, because a done/undone is a state rather than a quantity.
            if let add = entry.glasses, let existing = list[i].glasses {
                list[i].glasses = existing + add
            } else {
                list[i] = entry
            }
        } else {
            list.append(entry)
        }
        guard let data = try? JSONEncoder().encode(list) else { return }
        HabitsShared.defaults?.set(data, forKey: key)
    }

    /// Returns the queued changes and clears them, so each is applied exactly once.
    static func drain() -> [PendingToggle] {
        let list = load()
        if !list.isEmpty { HabitsShared.defaults?.removeObject(forKey: key) }
        return list
    }
}
