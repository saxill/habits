import Foundation
import SwiftData
import UserNotifications

/// A nudge per habit, at its own time, on its own days (§8: "local notifications for reminders
/// per habit/routine").
///
/// Sibling to `WaterReminders`, which handles the one special case where the reminder is a
/// stream of nudges through the day rather than a single time. Both write through the same
/// queue as the widgets, so a notification action and a tap in the app are one code path.
///
/// These are *local* notifications. Remote push (APNs) needs a paid Apple Developer Program
/// membership and a server to send from, so it is not what this app does — nor what the PRD
/// asks for. What matters for the user is identical: the phone buzzes at the right time with
/// the app closed.
enum HabitReminders {
    static let categoryId = "HABIT_REMINDER"
    static let doneAction = "HABIT_DONE"
    static let snoozeAction = "HABIT_SNOOZE"
    static let idPrefix = "habit."
    /// Named separately so a rebuild can leave snoozes alone: they share the prefix but are
    /// not part of the schedule, and sweeping them up took back a deferral the user had just
    /// asked for. (Habit ids are hex, so a real reminder's id can never start with "snooze".)
    static let snoozePrefix = "\(idPrefix)snooze"

    /// One-off requests are scheduled for the next few days rather than as one repeating
    /// weekly trigger per weekday.
    ///
    /// Repeating triggers are cheaper, and they are what this started as — but they cannot be
    /// skipped. A repeating reminder for a habit already ticked off still fires, and there is no
    /// way to withdraw just today's occurrence; the phone has no idea the work is done. A
    /// rolling window of concrete dates can be filtered at sync time, which is why "remind me at
    /// 08:00" goes quiet on a morning the habit is already checked. The window is re-armed every
    /// time the app comes forward.
    static let lookaheadDays = 7

    /// iOS keeps only the 64 soonest pending notifications and silently drops the rest, so the
    /// schedule is built soonest-first and truncated to fit. Water reminders are scheduled
    /// first and the habit ones fill what is left, because a hydration nudge that silently
    /// stops arriving is harder to notice than a missing habit reminder.
    static let totalBudget = 64
    static let reserve = 6

    static func registerCategory() {
        let done = UNNotificationAction(identifier: doneAction, title: "done", options: [])
        let snooze = UNNotificationAction(identifier: snoozeAction, title: "in 1h", options: [])
        let category = UNNotificationCategory(
            identifier: categoryId, actions: [done, snooze], intentIdentifiers: [], options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    // MARK: - Scheduling

    /// Every occurrence worth scheduling in the lookahead window, soonest first.
    ///
    /// Pure and separately testable: it is the part with the decisions in it (which days, which
    /// are already done, what is in the past), as opposed to the part that talks to the
    /// notification centre.
    static func occurrences(
        habits: [Habit],
        completionsByHabit: [UUID: Set<Date>],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [(habit: Habit, fire: Date)] {
        let today = calendar.startOfDay(for: now)
        var out: [(habit: Habit, fire: Date)] = []

        for habit in habits {
            guard let minutes = habit.reminderMinutesFromMidnight else { continue }
            let doneDays = completionsByHabit[habit.id] ?? []

            for offset in 0..<lookaheadDays {
                guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                      habit.scheduleDays.contains(calendar.component(.weekday, from: day))
                else { continue }
                // Today's nudge is pointless once the habit is ticked off — and the whole
                // reason this schedules concrete dates instead of a repeating trigger.
                if doneDays.contains(day) { continue }
                guard let fire = calendar.date(
                    bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day
                ), fire > now else { continue }
                out.append((habit, fire))
            }
        }
        return out.sorted { $0.fire < $1.fire }
    }

    /// Rebuilds the habit reminders from the store. Safe to call often — everything under
    /// `idPrefix` is cleared first, so an edit never leaves the old time behind.
    static func sync() {
        guard let context = HabitsApp.sharedContainer.map({ ModelContext($0) }),
              let habits = try? context.fetch(FetchDescriptor<Habit>())
        else { return }

        let byHabit = Dictionary(uniqueKeysWithValues: habits.map { habit in
            (habit.id, Set(habit.completions.map { $0.day.startOfDay() }))
        })
        let all = occurrences(habits: habits, completionsByHabit: byHabit)

        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let ours = pending.map(\.identifier)
                .filter { $0.hasPrefix(idPrefix) && !$0.hasPrefix(snoozePrefix) }
            center.removePendingNotificationRequests(withIdentifiers: ours)

            // What the water reminders will take, so the two schedulers share the cap rather
            // than assuming they are alone.
            let waterCount = pending.filter {
                $0.identifier.hasPrefix(WaterReminders.idPrefix)
                    && $0.identifier != WaterReminders.snoozeId
            }.count
            let budget = max(0, totalBudget - reserve - waterCount)

            for entry in all.prefix(budget) {
                let comps = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute], from: entry.fire
                )
                // Not repeating — the date is part of the trigger, so it fires once and stops.
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                center.add(request(for: entry.habit, at: entry.fire, trigger: trigger))
            }
        }
    }

    /// Defers one reminder by an hour, from the lock screen.
    ///
    /// The id is unique per habit and deferral, so snoozing two habits (or the same habit
    /// twice) keeps both nudges — a fixed id replaced the first snooze with the second.
    static func snooze(habitId: UUID?, day: Date?) {
        guard let habitId, let context = HabitsApp.sharedContainer.map({ ModelContext($0) }),
              let habit = try? context.fetch(FetchDescriptor<Habit>(predicate: #Predicate { $0.id == habitId })).first
        else { return }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false)
        let content = notificationContent(for: habit, day: day ?? Date())
        content.title = "> \(habit.name) (in 1h)"
        let stamp = ISO8601DateFormatter().string(from: Date())
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(
                identifier: "\(snoozePrefix).\(habitId.uuidString).\(stamp)",
                content: content, trigger: trigger
            )
        )
    }

    /// Clears every pending reminder for one habit — used when it is deleted, so a habit that no
    /// longer exists cannot buzz.
    static func cancel(habitId: UUID) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { pending in
            let ours = pending.filter {
                $0.identifier.hasPrefix(idPrefix)
                    && ($0.content.userInfo["habitId"] as? String) == habitId.uuidString
            }.map(\.identifier)
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ours)
        }
    }

    private static func request(for habit: Habit, at fire: Date, trigger: UNCalendarNotificationTrigger) -> UNNotificationRequest {
        // The date is in the id so two occurrences of the same habit are distinct requests.
        let stamp = ISO8601DateFormatter().string(from: fire)
        return UNNotificationRequest(
            identifier: "\(idPrefix)\(habit.id.uuidString).\(stamp)",
            content: notificationContent(for: habit, day: fire),
            trigger: trigger
        )
    }

    private static func notificationContent(for habit: Habit, day: Date) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "> \(habit.name)"
        let streak = Streaks.habitStreak(habit)
        var line = habit.comment.isEmpty
            ? (habit.routine.map { "// \($0.name.lowercased())" } ?? "// scheduled now")
            : habit.comment
        if streak > 1 { line += " · \(streak)d streak" }
        content.body = line
        content.sound = .default
        content.categoryIdentifier = categoryId
        content.userInfo = [
            "habitId": habit.id.uuidString,
            // The day it is *for*, not the day it was tapped — diagnostics and the sync use it.
            // Note: since 2026-09-28 past days cannot be completed, so a "done" actioned after
            // midnight for the previous day's reminder is dropped, not credited to yesterday.
            "day": ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: day)),
        ]
        return content
    }

    /// Pending habit reminders — surfaced in the profile diagnostic line.
    static func pendingCount() async -> Int {
        await UNUserNotificationCenter.current().pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix(idPrefix) }.count
    }

    /// Fires one reminder a few seconds out, on demand.
    ///
    /// Scheduling is invisible: a reminder that is correctly set for 08:00 looks exactly like
    /// one that will never arrive, and the first real evidence is either a buzz the next morning
    /// or silence. This makes it checkable in the moment — and it goes through the same content,
    /// category and actions as a real reminder, so what it proves is the real path.
    static func fireTest(in seconds: TimeInterval = 5) {
        let content: UNMutableNotificationContent
        let context = HabitsApp.sharedContainer.map { ModelContext($0) }
        let habits = (try? context?.fetch(FetchDescriptor<Habit>())) ?? []
        let withReminder = habits.first { $0.reminderMinutesFromMidnight != nil }

        if let habit = withReminder ?? WaterReminders.waterHabit(in: habits) {
            content = notificationContent(for: habit, day: Date())
            content.title = "> \(habit.name) (test)"
        } else {
            content = UNMutableNotificationContent()
            content.title = "> reminder test"
            content.body = "// set a reminder on a habit to see it here"
            content.categoryIdentifier = categoryId
        }
        content.sound = .default

        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: "\(idPrefix)test",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        ))
    }
}
