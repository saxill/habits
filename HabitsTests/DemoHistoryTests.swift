import XCTest
import SwiftData
@testable import Habits

/// Removing the made-up history an old first launch seeded.
///
/// The failure worth fearing is deleting a tick someone actually made, so most of these pin
/// what must survive: a tick today, a past day ticked afterwards, a habit added later.
@MainActor
final class DemoHistoryTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var defaults: UserDefaults!
    private let suite = "DemoHistoryTests"
    private let cal = Calendar.current

    /// The seed ran three days ago, mid-afternoon.
    private lazy var seedAt: Date = cal.date(byAdding: .day, value: -3,
                                             to: cal.date(bySettingHour: 15, minute: 0, second: 0, of: Date())!)!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: Habit.self, Completion.self, Routine.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
        defaults.set(true, forKey: SettingsKey.seeded)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        container = nil
        context = nil
    }

    private func habit(_ name: String, createdAt: Date) -> Habit {
        let h = Habit(name: name, icon: "circle", color: .cyan, type: .checkbox)
        h.createdAt = createdAt
        context.insert(h)
        return h
    }

    private func complete(_ habit: Habit, day: Date, at: Date) {
        let c = Completion(day: day, completedAt: at, value: 1)
        c.habit = habit
        context.insert(c)
    }

    private func daysBefore(_ n: Int, _ date: Date) -> Date {
        cal.date(byAdding: .day, value: -n, to: date)!
    }

    // MARK: the rule

    func testASeededCompletionIsRecognised() {
        let day = daysBefore(2, seedAt)
        XCTAssertTrue(DemoHistory.isSeeded(day: day.startOfDay(), completedAt: day,
                                           habitCreatedAt: seedAt, seedCreatedAt: seedAt))
    }

    func testATickOnOrAfterTheInstallDayIsKept() {
        XCTAssertFalse(DemoHistory.isSeeded(day: seedAt.startOfDay(), completedAt: seedAt,
                                            habitCreatedAt: seedAt, seedCreatedAt: seedAt))
    }

    /// Ticking a pre-install day later stamps it with the later moment.
    func testAPastDayTickedAfterwardsIsKept() {
        let day = daysBefore(1, seedAt).startOfDay()
        XCTAssertFalse(DemoHistory.isSeeded(day: day, completedAt: Date(),
                                            habitCreatedAt: seedAt, seedCreatedAt: seedAt))
    }

    func testAHabitAddedLaterIsNeverTouched() {
        let day = daysBefore(2, seedAt)
        XCTAssertFalse(DemoHistory.isSeeded(day: day.startOfDay(), completedAt: day,
                                            habitCreatedAt: seedAt.addingTimeInterval(86_400),
                                            seedCreatedAt: seedAt))
    }

    // MARK: the removal

    func testRemovesOnlySeededCompletionsAndOnlyOnce() throws {
        let read = habit("read", createdAt: seedAt)
        let water = habit("water", createdAt: seedAt.addingTimeInterval(1))
        let mine = habit("added later", createdAt: Date())

        // Seeded: before the install day, stamped on their own day.
        complete(read, day: daysBefore(1, seedAt), at: daysBefore(1, seedAt))
        complete(water, day: daysBefore(4, seedAt), at: daysBefore(4, seedAt))
        // Real: the install day, a pre-install day ticked afterwards, a later habit's today.
        complete(read, day: seedAt, at: seedAt)
        complete(water, day: daysBefore(1, seedAt), at: Date())
        complete(mine, day: Date(), at: Date())
        try context.save()

        XCTAssertEqual(DemoHistory.removeIfNeeded(context: context, defaults: defaults), 2)
        let left = try context.fetch(FetchDescriptor<Completion>())
        XCTAssertEqual(left.count, 3)
        XCTAssertTrue(left.allSatisfy { !cal.isDate($0.completedAt, inSameDayAs: $0.day) || $0.day >= seedAt.startOfDay() },
                      "a seeded-looking completion survived")

        // A second launch does nothing, even if something seeded-looking were still there.
        complete(read, day: daysBefore(2, seedAt), at: daysBefore(2, seedAt))
        try context.save()
        XCTAssertEqual(DemoHistory.removeIfNeeded(context: context, defaults: defaults), 0)
    }

    /// Installs from now on are seeded without history, and must never be swept.
    func testAnInstallThatNeverSeededHistoryIsLeftAlone() throws {
        defaults.set(true, forKey: SettingsKey.demoHistoryRemoved)
        let read = habit("read", createdAt: seedAt)
        complete(read, day: daysBefore(1, seedAt), at: daysBefore(1, seedAt))
        try context.save()
        XCTAssertEqual(DemoHistory.removeIfNeeded(context: context, defaults: defaults), 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Completion>()).count, 1)
    }
}
