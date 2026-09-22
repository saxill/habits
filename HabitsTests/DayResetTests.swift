import XCTest
import SwiftData
@testable import Habits

/// Clearing a day, and putting it back.
///
/// The scope and the receipt are the two things worth testing here: a reset that takes more than
/// the day it was asked for destroys history nobody agreed to lose, and a reset whose receipt is
/// lossy cannot honestly be offered as undoable.
final class DayResetTests: XCTestCase {

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

    private var yesterday: Date {
        Calendar.current.date(byAdding: .day, value: -1, to: Date())!
    }

    private func habit(_ name: String, type: HabitType = .checkbox) -> Habit {
        let h = Habit(name: name, icon: "circle", color: .cyan, type: type)
        context.insert(h)
        return h
    }

    @discardableResult
    private func complete(_ habit: Habit, on day: Date, value: Double = 1,
                          at: Date = Date()) -> Completion {
        let c = Completion(day: Calendar.current.startOfDay(for: day), completedAt: at, value: value)
        c.habit = habit
        context.insert(c)
        try? context.save()
        return c
    }

    /// Only the day asked for. The receipt is what makes a reset recoverable; the *scope* is what
    /// makes it safe to offer at all.
    ///
    /// Two habits, and the second one has no completion today at all — that is the shape that
    /// catches a reset which ignores the day: a habit whose only history is *not* today must come
    /// out of a reset of today completely untouched. An earlier version of this test used one
    /// habit with two completions, and a reset that deleted an arbitrary one of them passed it,
    /// because deleting the right one by luck looks exactly like deleting the right one on purpose.
    func testResetClearsOnlyTheChosenDay() {
        let todays = habit("run")
        complete(todays, on: Date())

        let earlier = habit("read")
        complete(earlier, on: yesterday)
        complete(earlier, on: Calendar.current.date(byAdding: .day, value: -2, to: Date())!)

        DayReset.reset(day: Date(), context: context)

        XCTAssertNil(todays.completion(on: Date()), "today should be cleared")
        XCTAssertEqual(earlier.completions.count, 2,
                       "a habit with no completion today lost history to a reset of today")
        XCTAssertNotNil(earlier.completion(on: yesterday), "yesterday must survive a reset of today")
        XCTAssertNotNil(earlier.completion(on: Calendar.current.date(byAdding: .day, value: -2, to: Date())!))
    }

    /// The receipt is exact — it carries the glass tally and the original timestamp, so an undo
    /// puts the day back as it was rather than a flattened version of it.
    func testTheReceiptCarriesTheValueAndTheTimestampBack() {
        let water = habit("glass of water")
        let logged = Date().addingTimeInterval(-3600)
        complete(water, on: Date(), value: 5, at: logged)

        let dropped = DayReset.reset(day: Date(), context: context)

        XCTAssertEqual(dropped.count, 1)
        XCTAssertEqual(dropped.first?.habitId, water.id)
        XCTAssertEqual(dropped.first?.value, 5, "the glass tally is part of the day")
        XCTAssertEqual(dropped.first?.completedAt, logged)

        DayReset.restore(dropped, context: context)

        XCTAssertEqual(water.completion(on: Date())?.value, 5)
        XCTAssertEqual(water.completion(on: Date())?.completedAt, logged)
    }

    /// An undo restores at most one completion per day. If the habit was logged again while the
    /// undo chip was on screen, what is on screen wins — one-per-habit-per-day is the invariant
    /// every streak, stat and achievement here is built on.
    func testUndoNeverMakesASecondCompletionForTheDay() {
        let h = habit("run")
        complete(h, on: Date())
        let dropped = DayReset.reset(day: Date(), context: context)

        // Logged again in the meantime — the case the undo must not double up on.
        complete(h, on: Date())

        DayReset.restore(dropped, context: context)

        let today = h.completions.filter { Calendar.current.isDate($0.day, inSameDayAs: Date()) }
        XCTAssertEqual(today.count, 1, "the undo made a second completion for the same day")
    }

    /// A running timer belongs to the day it was started on: today's goes, an older one is not
    /// this day's to stop.
    func testResetStopsTodaysTimerAndLeavesAnOlderOneRunning() {
        let todays = habit("claude session", type: .timed)
        let older = habit("research", type: .timed)
        todays.startTimer(at: Date())
        older.startTimer(at: Date().addingTimeInterval(-86_400 * 2))

        DayReset.reset(day: Date(), context: context)

        XCTAssertNil(todays.startedAt, "a timer started today belongs to the day being cleared")
        XCTAssertNotNil(older.startedAt, "a timer from an earlier day is not today's to stop")
    }

    /// The one thing an undo does not fully reverse: the session comes back *logged*, not running.
    /// The seconds survive, the clock does not.
    func testUndoRestoresASessionAsACompletionRatherThanARunningClock() {
        let h = habit("claude session", type: .timed)
        complete(h, on: Date(), value: 7260)
        let dropped = DayReset.reset(day: Date(), context: context)

        DayReset.restore(dropped, context: context)

        XCTAssertEqual(h.completion(on: Date())?.value, 7260)
        XCTAssertNil(h.startedAt, "the session should come back logged, not running again")
    }

    /// Nothing to clear is not a failure — an empty day resets to an empty day, and reports
    /// nothing to undo rather than a phantom receipt.
    func testResettingAnEmptyDayDropsNothing() {
        _ = habit("run")

        let dropped = DayReset.reset(day: Date(), context: context)

        XCTAssertTrue(dropped.isEmpty)
    }
}
