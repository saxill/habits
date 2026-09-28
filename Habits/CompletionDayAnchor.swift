import Foundation
import SwiftData

/// One-time migration: completions stored with a midnight day anchor move to noon.
///
/// Until 2026-09-28 a completion's `day` was the local midnight of its day, which shifts a
/// day when the device's time zone changes (see `Date.dayAnchor`). Existing rows are
/// re-anchored once — a row already at noon is left alone. Honest caveat: a row written in
/// one zone and migrated in a different one shifts by the zone change, which is exactly the
/// ambiguity the migration removes going forward.
enum CompletionDayAnchor {
    @discardableResult
    static func migrateIfNeeded(context: ModelContext, defaults: UserDefaults = .standard) -> Int {
        guard !defaults.bool(forKey: SettingsKey.completionDaysAnchored) else { return 0 }
        defer { defaults.set(true, forKey: SettingsKey.completionDaysAnchored) }

        let completions = (try? context.fetch(FetchDescriptor<Completion>())) ?? []
        var moved = 0
        for c in completions {
            let comps = Calendar.current.dateComponents([.hour, .minute], from: c.day)
            guard comps.hour == 0, comps.minute == 0 else { continue }
            c.day = c.day.dayAnchor()
            moved += 1
        }
        if moved > 0 { try? context.save() }

        #if DEBUG
        HabitsDebugLog.append("day anchor: moved \(moved) of \(completions.count) completions to noon")
        #endif
        return moved
    }
}