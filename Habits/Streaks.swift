import Foundation

/// All streak math is derived from Completion history — never stored (per PRD §7).
enum Streaks {

    /// Consecutive scheduled days (ending today, with a grace window through yesterday)
    /// on which the habit was completed.
    static func habitStreak(_ habit: Habit, today: Date = Date(), calendar: Calendar = .current) -> Int {
        let done = Set(habit.completions.map { $0.day.startOfDay(calendar: calendar) })
        guard !done.isEmpty else { return 0 }
        var streak = 0
        var cursor = today.startOfDay(calendar: calendar)
        // Today not done yet doesn't break the streak — walk back from today or yesterday.
        if !done.contains(cursor) { cursor = calendar.date(byAdding: .day, value: -1, to: cursor)! }
        while done.contains(cursor) {
            streak += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
        }
        return streak
    }

    /// Best streak ever for a habit (ignores schedule gaps — any completion counts).
    static func bestStreak(_ habit: Habit, calendar: Calendar = .current) -> Int {
        let days = habit.completions.map { $0.day.startOfDay(calendar: calendar) }.sorted()
        guard !days.isEmpty else { return 0 }
        var best = 1, run = 1
        for i in 1..<days.count {
            let gap = calendar.dateComponents([.day], from: days[i - 1], to: days[i]).day ?? 0
            run = gap == 1 ? run + 1 : 1
            best = max(best, run)
        }
        return best
    }

    /// Overall app streak: consecutive days (with today-grace) with at least one completion.
    static func overall(completions: [Completion], today: Date = Date(), calendar: Calendar = .current) -> Int {
        let done = Set(completions.map { $0.day.startOfDay(calendar: calendar) })
        guard !done.isEmpty else { return 0 }
        var cursor = today.startOfDay(calendar: calendar)
        if !done.contains(cursor) { cursor = calendar.date(byAdding: .day, value: -1, to: cursor)! }
        var streak = 0
        while done.contains(cursor) {
            streak += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
        }
        return streak
    }

    /// Completion ratio (0…1) for one habit on a given day — drives the week strip fill.
    static func dayRatio(_ day: Date, habits: [Habit], calendar: Calendar = .current) -> Double {
        let scheduled = habits.filter { $0.scheduleDays.contains(weekdayIndex(day, calendar: calendar)) }
        guard !scheduled.isEmpty else { return -1 } // no habits → empty
        let done = scheduled.filter { $0.completion(on: day, calendar: calendar) != nil }.count
        return Double(done) / Double(scheduled.count)
    }

    /// Calendar weekday as 1…7 (Sun…Sat, matching Calendar.weekday).
    static func weekdayIndex(_ day: Date, calendar: Calendar = .current) -> Int {
        calendar.component(.weekday, from: day)
    }
}