import XCTest
import SwiftData
@testable import Habits

/// The reminder schedule, asserted as exact dates rather than as "something got scheduled".
///
/// This is arithmetic over a calendar — which weekdays, what has already been ticked off, what
/// is already in the past — and every one of those has a failure mode that looks fine: a
/// reminder that quietly never fires on Sundays, or fires for a day already completed. Fixed
/// dates here, so a failure says which of those broke.
final class HabitReminderTests: XCTestCase {

    /// UTC, so "08:00" means 08:00 in the test no matter what the machine is set to.
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func habit(
        name: String = "stretch",
        minutes: Int? = 8 * 60,
        days: Set<Int> = [1, 2, 3, 4, 5, 6, 7],
        completedOn: [Date] = []
    ) -> Habit {
        let h = Habit(name: name, icon: "figure.flexibility", color: .cyan, type: .checkbox)
        h.reminderMinutesFromMidnight = minutes
        h.scheduleDays = days
        let _ = completedOn.map { day in
            let c = Completion(day: day, completedAt: day, value: 1)
            c.habit = h
            return c
        }
        return h
    }

    private func days(_ result: [(habit: Habit, fire: Date)]) -> [String] {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "E HH:mm"
        return result.map { f.string(from: $0.fire) }
    }

    /// 2026-09-21 is a Monday — asserted, so a calendar mistake here fails loudly instead of
    /// silently testing the wrong weekdays.
    func testFixtureDatesAreWhatTheTestsAssume() {
        XCTAssertEqual(calendar.component(.weekday, from: date(2026, 9, 21)), 2) // Mon
        XCTAssertEqual(calendar.component(.weekday, from: date(2026, 9, 26)), 7) // Sat
        XCTAssertEqual(calendar.component(.weekday, from: date(2026, 9, 27)), 1) // Sun
    }

    func testSchedulesEveryRemainingDayInTheWindow() {
        let h = habit()
        // Monday 07:00, reminder at 08:00 — seven days ahead, all scheduled.
        let found = HabitReminders.occurrences(
            habits: [h], completionsByHabit: [:], now: date(2026, 9, 21, 7), calendar: calendar
        )
        XCTAssertEqual(found.count, 7)
        XCTAssertEqual(days(found), [
            "Mon 08:00", "Tue 08:00", "Wed 08:00", "Thu 08:00",
            "Fri 08:00", "Sat 08:00", "Sun 08:00",
        ])
    }

    /// The reminder's own time has already passed today: it should skip today, not fire in the
    /// past, and not fall off the end of the window.
    func testTodaysReminderIsSkippedOnceItsTimeHasPassed() {
        let h = habit()
        let found = HabitReminders.occurrences(
            habits: [h], completionsByHabit: [:], now: date(2026, 9, 21, 9), calendar: calendar
        )
        XCTAssertEqual(days(found).first, "Tue 08:00")
        XCTAssertFalse(days(found).contains("Mon 08:00"))
    }

    /// Weekday-only habits must not nudge at the weekend — the whole reason the schedule field
    /// exists.
    func testWeekdayOnlyHabitSkipsTheWeekend() {
        let h = habit(days: [2, 3, 4, 5, 6]) // Mon–Fri
        let found = HabitReminders.occurrences(
            habits: [h], completionsByHabit: [:], now: date(2026, 9, 21, 7), calendar: calendar
        )
        XCTAssertEqual(days(found), [
            "Mon 08:00", "Tue 08:00", "Wed 08:00", "Thu 08:00", "Fri 08:00",
        ])
    }

    /// A habit already ticked off today goes quiet for today and comes back tomorrow. This is
    /// the behaviour that scheduling concrete dates exists for — a repeating trigger cannot do
    /// it.
    func testCompletedTodayIsSilentButTomorrowIsNot() {
        let h = habit()
        let today = calendar.startOfDay(for: date(2026, 9, 21))
        let found = HabitReminders.occurrences(
            habits: [h],
            completionsByHabit: [h.id: [today]],
            now: date(2026, 9, 21, 7),
            calendar: calendar
        )
        XCTAssertEqual(days(found).first, "Tue 08:00")
        XCTAssertFalse(days(found).contains("Mon 08:00"))
        XCTAssertEqual(found.count, 6)
    }

    /// A completion on another day must not silence anything.
    func testCompletionOnAnotherDayDoesNotSilenceToday() {
        let h = habit()
        let yesterday = calendar.startOfDay(for: date(2026, 9, 20))
        let found = HabitReminders.occurrences(
            habits: [h],
            completionsByHabit: [h.id: [yesterday]],
            now: date(2026, 9, 21, 7),
            calendar: calendar
        )
        XCTAssertTrue(days(found).contains("Mon 08:00"))
    }

    /// A habit with no reminder set contributes nothing — the field is optional and nil must not
    /// be read as midnight.
    func testHabitWithoutAReminderIsNotScheduled() {
        let h = habit(minutes: nil)
        XCTAssertTrue(HabitReminders.occurrences(
            habits: [h], completionsByHabit: [:], now: date(2026, 9, 21, 7), calendar: calendar
        ).isEmpty)
    }

    /// Soonest first, across habits. The scheduler truncates this list to fit iOS's 64-pending
    /// cap, so the order is what decides which reminders survive that cut.
    func testOccurrencesAreSortedSoonestFirstAcrossHabits() {
        let early = habit(name: "early", minutes: 7 * 60)
        let late = habit(name: "late", minutes: 20 * 60)
        let found = HabitReminders.occurrences(
            habits: [late, early], completionsByHabit: [:],
            now: date(2026, 9, 21, 6), calendar: calendar
        )
        XCTAssertEqual(found.first?.habit.name, "early")
        XCTAssertEqual(found.first?.fire, date(2026, 9, 21, 7))
        for (a, b) in zip(found, found.dropFirst()) {
            XCTAssertLessThanOrEqual(a.fire, b.fire)
        }
    }

    /// Midday and late reminders are ordinary times, not edge cases to round away.
    func testArbitraryMinuteIsKeptExactly() {
        let h = habit(minutes: 7 * 60 + 45)
        let found = HabitReminders.occurrences(
            habits: [h], completionsByHabit: [:], now: date(2026, 9, 21, 6), calendar: calendar
        )
        XCTAssertEqual(found.first?.fire, date(2026, 9, 21, 7, 45))
    }
}

/// The water schedule's arithmetic, which the interval and window chips in profile write to.
final class WaterReminderTests: XCTestCase {

    func testSlotsRunInclusiveOfTheEndHour() {
        let slots = WaterReminders.slots(startHour: 9, endHour: 21, intervalMinutes: 120)
        XCTAssertEqual(slots.count, 7)
        XCTAssertEqual(slots.map { $0.hour ?? -1 }, [9, 11, 13, 15, 17, 19, 21])
        XCTAssertTrue(slots.allSatisfy { ($0.minute ?? -1) == 0 })
    }

    func testHalfHourIntervalProducesHalfHourSlots() {
        let slots = WaterReminders.slots(startHour: 8, endHour: 20, intervalMinutes: 30)
        XCTAssertEqual(slots.count, 25)
        XCTAssertEqual(slots[1].minute, 30)
        XCTAssertEqual(slots.last?.hour, 20)
    }

    /// A window that ends before it starts, and an interval so short it would flood the cap,
    /// both produce nothing rather than something absurd.
    func testDegenerateWindowsAndIntervalsScheduleNothing() {
        XCTAssertTrue(WaterReminders.slots(startHour: 21, endHour: 9, intervalMinutes: 60).isEmpty)
        XCTAssertTrue(WaterReminders.slots(startHour: 9, endHour: 21, intervalMinutes: 5).isEmpty)
    }

    /// Every preset the UI offers must fit under iOS's 64-notification cap on its own, or the
    /// chips would schedule reminders that silently never arrive.
    func testEveryOfferedCombinationFitsTheSystemCap() {
        for preset in WaterReminders.windowPresets {
            for interval in WaterReminders.intervalChoices {
                let count = WaterReminders.slots(
                    startHour: preset.start, endHour: preset.end, intervalMinutes: interval
                ).count
                XCTAssertLessThanOrEqual(count, 64, "\(preset.label) every \(interval)m")
            }
        }
    }
}

/// Logging a glass, against a real (in-memory) store.
///
/// This is the part that was broken in a way arithmetic alone could not show: "log glass"
/// recorded a *day done*, and a day can only be done once — so the count read `1/8` after the
/// first glass and stayed there. These assert the tally actually moves, and that moving it did
/// not quietly change what "done" means to streaks and achievements.
final class WaterGlassTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: Habit.self, Completion.self, Routine.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
    }

    override func tearDown() {
        container = nil
        context = nil
    }

    /// The glass habit, named and shaped like a real one rather than using the drop icon, since
    /// name-matching is the path that matters when someone renames a habit.
    private func waterHabit(name: String = "glass of water") -> Habit {
        let h = Habit(name: name, icon: "circle", color: .blue, type: .checkbox)
        context.insert(h)
        return h
    }

    private func logGlasses(_ n: Int, for habit: Habit, on day: Date = Date()) {
        for _ in 0..<n {
            PendingToggleQueue.logGlass(habitId: habit.id, day: day)
        }
        PendingToggleApplier.apply(context: context)
    }

    /// The whole point: a second glass adds to the first instead of being swallowed.
    func testEachGlassAddsToTheDaysTally() {
        let habit = waterHabit()
        XCTAssertEqual(WaterReminders.glasses(for: habit), 0)

        logGlasses(1, for: habit)
        XCTAssertEqual(WaterReminders.glasses(for: habit), 1, "first glass")

        logGlasses(2, for: habit)
        XCTAssertEqual(WaterReminders.glasses(for: habit), 3, "glasses must accumulate, not replace")
    }

    /// One completion a day still — the invariant every derived stat rests on. The tally rides in
    /// `value` precisely so that this stays true. Logged in two batches so the *second* batch has
    /// to land on the existing completion rather than making a new one.
    func testTheTallyNeverCreatesASecondCompletion() {
        let habit = waterHabit()
        logGlasses(3, for: habit)
        logGlasses(2, for: habit)

        let today = Calendar.current.startOfDay(for: Date())
        let completions = habit.completions.filter {
            Calendar.current.isDate($0.day, inSameDayAs: today)
        }
        XCTAssertEqual(completions.count, 1, "a day must stay a single completion")
        XCTAssertEqual(completions.first?.value, 5)
    }

    /// Logging an older day credits that day, and does not touch today. Two batches per day, so
    /// both days have to accumulate onto a completion that already exists.
    func testGlassesAreCountedPerDay() {
        let habit = waterHabit()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!

        logGlasses(3, for: habit, on: yesterday)
        logGlasses(1, for: habit, on: yesterday)
        logGlasses(1, for: habit)
        logGlasses(1, for: habit)

        XCTAssertEqual(WaterReminders.glasses(on: yesterday, for: habit), 4)
        XCTAssertEqual(WaterReminders.glasses(for: habit), 2)
    }

    /// Queueing twice before the app applies them must be two glasses. The queue replaces entries
    /// per habit/day, which is right for a done/undone and wrong for a quantity.
    func testTwoQueuedGlassesBeforeApplyingAreBothCounted() {
        let habit = waterHabit()
        let today = Date()
        PendingToggleQueue.logGlass(habitId: habit.id, day: today)
        PendingToggleQueue.logGlass(habitId: habit.id, day: today)
        PendingToggleApplier.apply(context: context)

        XCTAssertEqual(WaterReminders.glasses(for: habit), 2)
        PendingToggleQueue.drain() // leave no residue for the next test
    }

    /// A timed habit keeps seconds in `value`, so it must never be treated as a water tracker —
    /// otherwise a 1,800-second focus session reads as 1,800 glasses.
    func testATimedHabitIsNeverMistakenForWater() {
        let timed = Habit(name: "water break stretch", icon: "drop", color: .cyan, type: .timed)
        context.insert(timed)
        XCTAssertFalse(WaterReminders.isWaterHabit(timed))

        let checkoff = Habit(name: "glass of water", icon: "circle", color: .blue, type: .checkbox)
        context.insert(checkoff)
        XCTAssertTrue(WaterReminders.isWaterHabit(checkoff))
    }

    /// The regression this change introduced and then had to guard: a glass tally in `value`
    /// would otherwise hand out the "ran a timed session" achievement for free.
    func testAGlassTallyDoesNotUnlockTheTimedSessionAchievement() {
        let habit = waterHabit()
        logGlasses(5, for: habit)

        let facts = Achievements.facts(habits: [habit])
        XCTAssertFalse(facts.hasTimedSession, "logging water is not a timed session")
    }

    /// ...and a real timed session still does unlock it, so the guard is not simply always-false.
    func testATimedSessionStillUnlocksTheTimedSessionAchievement() {
        let timed = Habit(name: "focus block", icon: "brain.head.profile", color: .blue, type: .timed)
        context.insert(timed)
        let c = Completion(day: Calendar.current.startOfDay(for: Date()),
                           completedAt: Date(), value: 1800)
        c.habit = timed
        context.insert(c)

        XCTAssertTrue(Achievements.facts(habits: [timed]).hasTimedSession)
    }
}
