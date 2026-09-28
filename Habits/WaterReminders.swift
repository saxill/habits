import Foundation
import SwiftData
import UserNotifications

/// Hydration nudges: daily repeating local notifications across a waking-hours window,
/// with lock-screen actions to log a glass or push the reminder back an hour.
enum WaterReminders {
    static let categoryId = "WATER_REMINDER"
    static let logGlassAction = "WATER_LOG_GLASS"
    static let snoozeAction = "WATER_SNOOZE"
    static let idPrefix = "water."
    /// Named separately so a rebuild can leave it alone: it shares the prefix but is not part of
    /// the schedule, and sweeping it up took back a snooze the user had just asked for.
    static let snoozeId = "water.snooze"

    /// How many days of concrete reminders are kept scheduled.
    ///
    /// This started as one repeating trigger per slot — cheap, but repeating triggers freeze
    /// their content, so the first reminder after midnight still quoted *yesterday's* glass
    /// count. A rolling window of concrete requests is rebuilt with each day's own tally,
    /// the same way HabitReminders works; the app re-arms it every activation.
    static let lookaheadDays = 2

    /// Glasses a full day is worth, used for the "N/8" line in the reminder body.
    static let goal = 8

    static let intervalChoices = [30, 60, 120, 180]
    static let windowPresets: [(start: Int, end: Int, label: String)] = [
        (8, 20, "08–20"), (9, 21, "09–21"), (10, 22, "10–22"), (7, 19, "07–19"),
    ]

    // MARK: - Scheduling

    /// Reminder slots across the window, inclusive of the end hour.
    static func slots(startHour: Int, endHour: Int, intervalMinutes: Int) -> [DateComponents] {
        guard endHour > startHour, intervalMinutes >= 15 else { return [] }
        var out: [DateComponents] = []
        var minutes = startHour * 60
        while minutes <= endHour * 60 {
            out.append(DateComponents(hour: minutes / 60, minute: minutes % 60))
            minutes += intervalMinutes
        }
        return out
    }

    static func registerCategory() {
        let log = UNNotificationAction(identifier: logGlassAction, title: "log glass", options: [])
        let snooze = UNNotificationAction(identifier: snoozeAction, title: "in 1h", options: [])
        let category = UNNotificationCategory(
            identifier: categoryId, actions: [log, snooze], intentIdentifiers: [], options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Rebuilds every reminder from the stored settings. Safe to call often — it clears the
    /// previous set first, so interval or window changes never leave stale notifications.
    static func sync() {
        let d = UserDefaults.standard
        let enabled = d.object(forKey: SettingsKey.waterRemindersEnabled) as? Bool ?? false
        let start = d.object(forKey: SettingsKey.waterStartHour) as? Int ?? 9
        let end = d.object(forKey: SettingsKey.waterEndHour) as? Int ?? 21
        let interval = d.object(forKey: SettingsKey.waterInterval) as? Int ?? 120

        let habit = currentWaterHabit()

        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let ours = pending.map(\.identifier)
                .filter { $0.hasPrefix(idPrefix) && !$0.hasPrefix("\(idPrefix)snooze") }
            center.removePendingNotificationRequests(withIdentifiers: ours)
            guard enabled else { return }
            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            for offset in 0..<lookaheadDays {
                guard let day = cal.date(byAdding: .day, value: offset, to: today) else { continue }
                // Each day's reminders quote *that day's* tally — zero for tomorrow until
                // the app rebuilds the window, never the count from the day before.
                let glasses = glasses(on: day, for: habit)
                for comps in slots(startHour: start, endHour: end, intervalMinutes: interval) {
                    let minutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
                    guard let fire = cal.date(
                        bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day
                    ), fire > Date() else { continue }
                    center.add(request(for: fire, habit: habit, glasses: glasses))
                }
            }
        }
    }

    /// Defers one reminder by an hour (the "in 1h" lock-screen action).
    static func snooze(minutes: Int = 60, habitId: UUID?) {
        let habit = currentWaterHabit()
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(minutes * 60), repeats: false
        )
        // Built from the live tally, so a snoozed reminder quotes the current count rather than
        // the one from whenever the day's schedule was last rebuilt.
        let content = notificationContent(habit: habit, glasses: glasses(for: habit))
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: snoozeId, content: content, trigger: trigger)
        )
    }

    private static func request(for fire: Date, habit: Habit?, glasses: Int) -> UNNotificationRequest {
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents(fire), repeats: false)
        // The timestamp is in the id so every occurrence is its own request — the way the
        // habit reminders do it.
        let stamp = ISO8601DateFormatter().string(from: fire)
        return UNNotificationRequest(
            identifier: "\(idPrefix)\(stamp)",
            content: notificationContent(habit: habit, glasses: glasses),
            trigger: trigger
        )
    }

    /// Y/M/D/H/M of one fire date, the unit a non-repeating trigger takes.
    private static func dateComponents(_ fire: Date) -> DateComponents {
        Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
    }

    private static func notificationContent(habit: Habit?, glasses: Int) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "> drink water"
        content.body = habit == nil
            ? "// hydration check — grab a glass"
            : "// \(glasses)/\(goal) glasses today — log one?"
        content.sound = .default
        content.categoryIdentifier = categoryId
        if let habit { content.userInfo = ["habitId": habit.id.uuidString] }
        return content
    }

    // MARK: - Water habit lookup

    /// The habit reminders count against: the one using a water drop, else a name match.
    ///
    /// Check-off only. A *timed* habit keeps seconds in `Completion.value`, and this feature
    /// reads that field as a glass tally — so a timed habit that happened to be called "water"
    /// would have its reminder claim it had logged 1,800 glasses.
    static func isWaterHabit(_ habit: Habit) -> Bool {
        guard habit.type == .checkbox else { return false }
        if habit.icon == "drop" { return true }
        let n = habit.name.lowercased()
        return n.contains("water") || n.contains("hydrat")
    }

    static func waterHabit(in habits: [Habit]) -> Habit? {
        // Drop icon first: the surest signal, and it wins even if an earlier habit name-matches.
        habits.first { $0.icon == "drop" && $0.type == .checkbox }
            ?? habits.first(where: isWaterHabit)
    }

    static func currentWaterHabit() -> Habit? {
        guard let container = HabitsApp.sharedContainer else { return nil }
        let habits = (try? ModelContext(container).fetch(FetchDescriptor<Habit>())) ?? []
        return waterHabit(in: habits)
    }

    /// Glasses logged for the water habit on a day — the tally carried in the day's completion
    /// `value`. Zero when nothing has been logged.
    static func glasses(on day: Date = Date(), for habit: Habit?) -> Int {
        guard let habit else { return 0 }
        return Int(habit.completion(on: day)?.value ?? 0)
    }

    /// Adds a glass to the day, through the same queue the widgets use so a notification action
    /// and a tap in the app are one code path.
    ///
    /// Goes through the queue rather than editing the model here because the write has to land in
    /// the *main* context — a fresh context does save, but the views' own copy then republishes
    /// over the top of it ([[habits-term-app]]).
    @MainActor
    static func logGlass(habitId: UUID? = nil, day: Date = Date()) {
        guard let container = HabitsApp.sharedContainer else { return }
        let target = habitId.flatMap { id in
            (try? ModelContext(container)
                .fetch(FetchDescriptor<Habit>(predicate: #Predicate { $0.id == id })).first)
        } ?? currentWaterHabit()
        guard let habit = target else { return }

        PendingToggleQueue.logGlass(habitId: habit.id, day: day)
        SnapshotPublisher.publish(context: container.mainContext)
        // Rebuild the schedule so the rest of the day's reminders quote the new tally rather than
        // the one frozen in when they were last added.
        HabitReminders.sync()
        WaterReminders.sync()
    }

    /// Pending reminder count — surfaced in the profile diagnostic line. A pending snooze is not
    /// counted: it is one deferred nudge, not a slot in the day, and counting it made the line
    /// disagree with the interval and window shown right above it.
    static func pendingCount() async -> Int {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        return pending.filter { $0.identifier.hasPrefix(idPrefix) && $0.identifier != snoozeId }.count
    }
}
