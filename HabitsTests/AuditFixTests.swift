import XCTest
import SwiftData
@testable import Habits

/// The audit fixes of 2026-09-28, each pinned so it cannot quietly regress:
/// the queue's merge rules, an un-tick that must not stop today's timer, the week strip's
/// pre-creation days, the noon day anchor and its migration, and the DST-at-midnight walk.
@MainActor
final class AuditFixTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var defaults: UserDefaults!
    private let suite = "AuditFixTests"
    private let cal = Calendar.current

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: Habit.self, Completion.self, Routine.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
        // The queue is a shared app-group defaults; start every test from an empty queue.
        HabitsShared.defaults?.removeObject(forKey: "habits.pendingToggles.v1")
    }

    override func tearDown() {
        HabitsShared.defaults?.removeObject(forKey: "habits.pendingToggles.v1")
        defaults.removePersistentDomain(forName: suite)
        container = nil
        context = nil
    }

    private func habit(
        _ name: String = "read",
        type: HabitType = .checkbox,
        days: Set<Int> = [1, 2, 3, 4, 5, 6, 7]
    ) -> Habit {
        let h = Habit(name: name, icon: "book", color: .purple, type: type)
        h.scheduleDays = days
        context.insert(h)
        return h
    }

    private func toggle(_ habit: Habit, _ day: Date, _ done: Bool) {
        PendingToggleQueue.set(habitId: habit.id, day: day, done: done)
    }

    // MARK: the queue merges instead of replacing

    /// The bug: a widget tick, then a live-activity pause, arrived in that order — and the
    /// pause entry replaced the tick, so the habit was never recorded.
    func testAQueuedTickSurvivesALaterPause() {
        let h = habit(type: .timed)
        h.startTimer()
        toggle(h, Date(), true)
        PendingToggleQueue.setPaused(habitId: h.id, paused: true)

        PendingToggleApplier.apply(context: context)
        XCTAssertNil(h.startedAt, "the tick stops the timer and records the run")
        XCTAssertNotNil(h.completion(on: Date()), "the tick must survive the pause that followed it")
    }

    /// A pause-only entry must not un-tick the day it arrived on (`done == false` there is
    /// a placeholder, not an instruction).
    func testAPauseOnlyEntryDoesNotUntickADoneDay() {
        let h = habit()
        let c = Completion(day: Date().startOfDay().dayAnchor(), completedAt: Date(), value: 1)
        c.habit = h
        context.insert(c)
        try? context.save()

        PendingToggleQueue.setPaused(habitId: h.id, paused: true)
        PendingToggleApplier.apply(context: context)
        XCTAssertNotNil(h.completion(on: Date()), "pausing must not undo the day")
    }

    /// "Discard" means log nothing: it supersedes a tick queued a moment earlier.
    func testDiscardSupersedesAQueuedTick() {
        let h = habit(type: .timed)
        h.startTimer()
        toggle(h, Date(), true)
        PendingToggleQueue.stopTimer(habitId: h.id)

        PendingToggleApplier.apply(context: context)
        XCTAssertNil(h.completion(on: Date()), "discard must not log")
        XCTAssertNil(h.startedAt, "discard must stop the timer")
    }

    // MARK: un-ticking and the running timer

    /// The bug: un-ticking *yesterday* called clearTimer unconditionally, killing a timer
    /// that was running for today.
    func testUntickingAPastDayKeepsTodaysRunningTimer() {
        let h = habit(type: .timed)
        h.startTimer()
        let yesterday = cal.date(byAdding: .day, value: -1, to: Date())!
        let c = Completion(day: yesterday.startOfDay().dayAnchor(), completedAt: yesterday, value: 1)
        c.habit = h
        context.insert(c)
        try? context.save()

        toggle(h, yesterday, false)
        PendingToggleApplier.apply(context: context)
        XCTAssertNil(h.completion(on: yesterday), "the past day is un-ticked")
        XCTAssertNotNil(h.startedAt, "today's timer must keep running")
    }

    /// And un-ticking a day that *was* ticked really does stop a timer started that day.
    func testUntickingTodayStopsTheTimer() {
        let h = habit(type: .timed)
        h.startTimer()
        toggle(h, Date(), true)          // tick: the timed branch records and stops the run
        PendingToggleApplier.apply(context: context)
        XCTAssertNil(h.startedAt)
        XCTAssertNotNil(h.completion(on: Date()))
    }

    // MARK: yesterday cannot be completed

    /// A widget or notification tap cannot tick a past day. Un-ticking stays legal —
    /// corrections are allowed, backfilling is not.
    func testATickForAPastDayIsDropped() {
        let h = habit()
        let yesterday = cal.date(byAdding: .day, value: -1, to: Date())!
        toggle(h, yesterday, true)
        PendingToggleApplier.apply(context: context)
        XCTAssertNil(h.completion(on: yesterday), "yesterday must stay unticked")
        XCTAssertTrue(h.completions.isEmpty, "no completion may be created for a past day")
    }

    /// Today is still tickable through the same queue, so the block targets the day, not
    /// the path.
    func testTodayIsStillTickableThroughTheQueue() {
        let h = habit()
        toggle(h, Date(), true)
        PendingToggleApplier.apply(context: context)
        XCTAssertNotNil(h.completion(on: Date()))
    }

    // MARK: the week strip before a habit existed

    /// A habit created this month must not mark last month's days as missed (ratio 0);
    /// before its history begins the day is simply empty (ratio -1).
    func testDayRatioIsEmptyBeforeTheHabitWasTracked() {
        let h = habit()
        h.createdAt = Date()
        context.insert(h)
        let threeDaysAgo = cal.date(byAdding: .day, value: -3, to: Date())!
        XCTAssertEqual(Streaks.dayRatio(threeDaysAgo, habits: [h]), -1, "pre-creation days are empty, not missed")
        XCTAssertEqual(Streaks.dayRatio(Date(), habits: [h]), 0, "today is scheduled and missed")
    }

    // MARK: the noon day anchor

    /// New completions are stored at noon of their day, and every read still matches them.
    func testNewCompletionsAnchorAtNoon() {
        let h = habit()
        let c = Completion(day: Date().startOfDay().dayAnchor(), completedAt: Date(), value: 1)
        c.habit = h
        context.insert(c)
        XCTAssertEqual(cal.component(.hour, from: c.day), 12)
        XCTAssertTrue(h.completion(on: Date()) === c, "reads go through the calendar day either way")
    }

    func testDayAnchorMigrationMovesMidnightsOnce() throws {
        defaults.removeObject(forKey: SettingsKey.completionDaysAnchored)
        let h = habit()
        let day = Date().startOfDay()
        let c = Completion(day: day, completedAt: day, value: 1)
        c.day = day   // the old build's stored shape — the init now anchors to noon itself
        c.habit = h
        context.insert(c)
        try context.save()

        XCTAssertEqual(CompletionDayAnchor.migrateIfNeeded(context: context, defaults: defaults), 1)
        XCTAssertEqual(cal.component(.hour, from: c.day), 12)
        XCTAssertEqual(c.day.startOfDay(), day, "the calendar day itself must not move")
        // Idempotent: a second launch must not touch anything.
        XCTAssertEqual(CompletionDayAnchor.migrateIfNeeded(context: context, defaults: defaults), 0)
    }

    // MARK: the DST-at-midnight day walk

    /// Chile moves its clock exactly at midnight (24:00 on the first Saturday of September),
    /// so midnight does not exist on the morning after: `startOfDay` is 01:00. A walk that
    /// steps with a raw `date(byAdding: .day)` drifts off the midnight grid its `done` set
    /// is built from and stops early — the streak loses a day. Fixture asserted, so a change
    /// in the zone's rule fails loudly here instead of silently testing nothing.
    func testStreakWalkSurvivesAMidnightDSTJump() throws {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Santiago")!
        c.locale = Locale(identifier: "en_US_POSIX")

        let today = try XCTUnwrap(c.date(from: DateComponents(year: 2026, month: 9, day: 6, hour: 12)))
        let start = today.startOfDay(calendar: c)
        XCTAssertEqual(c.component(.hour, from: start), 1,
                       "the fixture assumes a spring-forward at midnight on 2026-09-06")

        let h = habit()
        for offset in [0, -1] {
            let day = try XCTUnwrap(c.date(byAdding: .day, value: offset, to: today))
            let comp = Completion(day: day.dayAnchor(calendar: c), completedAt: day, value: 1)
            comp.habit = h
            context.insert(comp)
        }
        try context.save()
        XCTAssertEqual(Streaks.habitStreak(h, today: today, calendar: c), 2)
    }
}