import Foundation
import SwiftData

/// The fake history an earlier first launch backfilled, and its removal.
///
/// Until 2026-09-25 the seed wrote nine days of made-up completions before the install
/// day so stats looked alive on first open. They look real everywhere — stats, streaks,
/// achievements, XP — so they have to go, and only they may go.
///
/// A seeded completion has a fingerprint no real one can: it belongs to a habit the seed
/// created, it's dated *before* the install day, and its timestamp falls on that same day.
/// A tick you make is stamped with the moment you tapped, so even a past day you ticked
/// afterwards (tapped today, for yesterday) carries a later stamp and is kept.
enum DemoHistory {
    /// Seeded habits are all created in the same instant; allow a little slack.
    static let seedWindow: TimeInterval = 120

    static func isSeeded(day: Date, completedAt: Date, habitCreatedAt: Date,
                         seedCreatedAt: Date, calendar: Calendar = .current) -> Bool {
        abs(habitCreatedAt.timeIntervalSince(seedCreatedAt)) <= seedWindow
            && day < seedCreatedAt.startOfDay(calendar: calendar)
            && calendar.isDate(completedAt, inSameDayAs: day)
    }

    /// Removes the seeded completions once, through the context the views read.
    /// Returns how many went.
    @MainActor
    @discardableResult
    static func removeIfNeeded(context: ModelContext, defaults: UserDefaults = .standard) -> Int {
        guard defaults.bool(forKey: SettingsKey.seeded),
              !defaults.bool(forKey: SettingsKey.demoHistoryRemoved) else { return 0 }
        defer { defaults.set(true, forKey: SettingsKey.demoHistoryRemoved) }

        let habits = (try? context.fetch(FetchDescriptor<Habit>())) ?? []
        // The seed created every habit it made in one go, before anything else existed.
        guard let seedCreatedAt = habits.map(\.createdAt).min() else { return 0 }

        let completions = (try? context.fetch(FetchDescriptor<Completion>())) ?? []
        let seeded = completions.filter { completion in
            guard let habit = completion.habit else { return false }
            return isSeeded(day: completion.day, completedAt: completion.completedAt,
                            habitCreatedAt: habit.createdAt, seedCreatedAt: seedCreatedAt)
        }
        seeded.forEach(context.delete)
        try? context.save()

        #if DEBUG
        let days = Set(seeded.map(\.day)).sorted()
        HabitsDebugLog.append("demo history: removed \(seeded.count) of \(completions.count) completions"
            + (days.isEmpty ? "" : " (\(days.first!.formatted(date: .abbreviated, time: .omitted))…\(days.last!.formatted(date: .abbreviated, time: .omitted)))"))
        #endif
        return seeded.count
    }
}
