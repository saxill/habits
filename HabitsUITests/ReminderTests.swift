import XCTest

/// Reminders, driven through the real UI.
///
/// The unit tests in `HabitsTests` cover which reminders *should* be scheduled. They cannot
/// cover whether anything is scheduled at all: permission, the sync into the notification
/// centre, and a banner actually appearing are all outside the app's own arithmetic. Those are
/// what this file checks — a reminder that is computed correctly and never delivered looks
/// exactly like a working one from inside the app.
final class ReminderTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private var springboard: XCUIApplication {
        XCUIApplication(bundleIdentifier: "com.apple.springboard")
    }

    /// Grants the permission prompt if it is up. Conditional because iOS only asks once per
    /// install: on a later run the answer is already recorded and there is no alert, and a test
    /// that insists on tapping it would fail for that reason instead of a real one.
    private func grantNotificationsIfAsked() {
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: 6) { allow.tap() }
    }

    /// The `system: ... scheduled today` line in profile, read as the numbers it reports.
    private func scheduledCounts(_ app: XCUIApplication) -> (water: Int, habit: Int)? {
        let matches = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'scheduled today'"))
        guard matches.count > 0 else { return nil }
        let label = matches.element(boundBy: 0).label
        let numbers = label.split(separator: " ")
            .compactMap { Int($0) }
        // "allowed · 7 water · 14 habit scheduled today" → [7, 14]
        guard numbers.count >= 2 else { return nil }
        return (numbers[0], numbers[1])
    }

    /// Leaves water reminders on, whichever state they started in.
    ///
    /// The setting persists across launches — it is a `@AppStorage` flag — so a test that taps
    /// the toggle unconditionally turns it *off* on any run after the first, and then reports
    /// the absence it caused.
    private func ensureWaterRemindersOn(_ app: XCUIApplication) {
        let toggle = app.buttons["remind me to drink water"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "water toggle not found")
        if (toggle.value as? String) != "on" {
            toggle.tap()
            grantNotificationsIfAsked()
        }
    }

    /// Turning water reminders on asks for permission and schedules a day's worth of nudges —
    /// and the count the profile reports is checked against the interval that was chosen, so it
    /// cannot pass by scheduling the wrong thing.
    func testEnablingWaterRemindersSchedulesADaysWorth() {
        let app = XCUIApplication()
        app.launchEnvironment["DEBUG_TAB"] = "profile"
        app.launch()

        ensureWaterRemindersOn(app)

        // Default window is 09–21 at 2h → 07:00, 09:00 … 21:00, seven slots.
        var counts: (water: Int, habit: Int)?
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            counts = scheduledCounts(app)
            if let c = counts, c.water > 0 { break }
            usleep(300_000)
        }
        XCTAssertEqual(counts?.water, 7, "expected a 09–21 window at 2h to schedule 7 reminders")
    }

    /// The test-fire chip: one notification, five seconds out, through the same content and
    /// category a real reminder uses. This is the only thing in the suite that proves a
    /// notification is *delivered* rather than merely scheduled.
    func testTestReminderIsActuallyDelivered() {
        let app = XCUIApplication()
        app.launchEnvironment["DEBUG_TAB"] = "profile"
        app.launch()

        // Permission first: a reminder that cannot be shown proves nothing about delivery.
        ensureWaterRemindersOn(app)

        let test = app.buttons["test"]
        XCTAssertTrue(test.waitForExistence(timeout: 5), "test chip not found")
        test.tap()

        // The app is in the foreground, so the banner is presented over its own window; if the
        // system hands it to springboard instead, it is found there. Checking both, because
        // which one it is has changed between iOS releases and neither is worth a flake.
        let deadline = Date().addingTimeInterval(20)
        var seen = false
        while Date() < deadline && !seen {
            let inApp = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS 'test'")
            ).count > 0
            let inSystem = springboard.staticTexts.matching(
                NSPredicate(format: "label CONTAINS 'test'")
            ).count > 0
            seen = inApp || inSystem
            if !seen { usleep(400_000) }
        }
        XCTAssertTrue(seen, "no reminder banner appeared within 20s of the test fire")
    }

    /// Setting a reminder on a habit, through the editor, schedules it and shows it on the row.
    ///
    /// The row is asserted rather than the profile count so the check covers the whole path —
    /// editor → model → row — and the profile line is checked separately afterwards for the
    /// scheduling half.
    func testSettingAReminderInTheEditorShowsOnTheRowAndSchedules() {
        let app = XCUIApplication()
        app.launchEnvironment["DEBUG_TAB"] = "habits"
        app.launch()

        // Any seeded habit will do; "stretch" is in the first routine.
        let row = app.staticTexts["stretch"]
        XCTAssertTrue(row.waitForExistence(timeout: 6), "no habit rows found")
        row.press(forDuration: 1.2)

        let edit = app.buttons["edit habit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "context menu did not open")
        edit.tap()

        // The reminder section is the last one in the form, so it starts below the fold and is
        // not in the accessibility tree at all until it is scrolled to.
        let matches = app.descendants(matching: .any).matching(identifier: "remind me")
        let form = app.collectionViews.firstMatch
        XCTAssertTrue(form.waitForExistence(timeout: 5), "editor form not found")
        var scrolls = 0
        while matches.firstMatch.exists == false && scrolls < 6 {
            form.swipeUp()
            scrolls += 1
        }
        let control = matches.firstMatch
        XCTAssertTrue(control.waitForExistence(timeout: 5),
                      "reminder toggle not found in editor after \(scrolls) scrolls")

        // The switch itself, not whatever wrapper carries the same identifier — tapping a row
        // that merely contains a switch does not flip it.
        // The switch is reported as the whole row (370pt wide), so a centre tap lands on the
        // label rather than the control. Tapping where the control actually sits — the trailing
        // edge — is what a thumb does, and it is what flips it.
        if (control.value as? String) != "1" {
            control.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            usleep(1_200_000)
        }
        XCTAssertEqual((control.value as? String), "1", "the reminder toggle did not turn on")

        let save = app.buttons["save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "save button not found")
        save.tap()

        // Default reminder time is 08:00, and the row reports the setting as a clock time.
        //
        // Matched against the whole row rather than a "08:00" text of its own: the row is one
        // combined accessibility element, so its parts are merged into its label and a query for
        // the time alone would never match, however correct the row was.
        let withReminder = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS 'reminder 08:00'")
        ).firstMatch
        if !withReminder.waitForExistence(timeout: 6) {
            let stretchLabels = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS 'stretch'"))
                .allElementsBoundByIndex.map { "\($0.elementType.rawValue): \($0.label)" }
            XCTFail("row does not show the reminder. stretch elements: \(stretchLabels)")
        }

        // ...and the schedule itself. Swiping to profile is the app's own navigation.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
        start.press(forDuration: 0.05, thenDragTo: end)

        var habitCount = 0
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if let c = scheduledCounts(app), c.habit > 0 { habitCount = c.habit; break }
            usleep(300_000)
        }
        XCTAssertGreaterThan(habitCount, 0, "no habit reminders were scheduled after saving one")
    }

    /// Reading the tally, tapping `+ glass` in profile, and checking the number actually moved.
    ///
    /// The unit tests prove the arithmetic; they cannot prove the chip is wired to it or that the
    /// number on screen comes from the store. This is the join between the two — and it is the
    /// exact thing that was broken before: a "log glass" that recorded a day-done could only ever
    /// report 1 of 8, so the button looked connected and the count never changed.
    func testLoggingAGlassFromProfileAdvancesTheTally() {
        let app = XCUIApplication()
        app.launchEnvironment["DEBUG_TAB"] = "profile"
        app.launch()

        let tally = app.staticTexts.matching(
            NSPredicate(format: "label ENDSWITH 'glasses today'")
        ).firstMatch
        XCTAssertTrue(tally.waitForExistence(timeout: 6),
                      "no glass tally in profile — is there a water habit?")

        // Read it rather than assuming a starting number: the simulator's store persists between
        // runs, so a hardcoded expectation would pass once and then fail forever after.
        let before = glasses(in: tally.label)
        XCTAssertNotNil(before, "could not read a count out of \"\(tally.label)\"")

        let add = app.buttons["+ glass"]
        XCTAssertTrue(add.waitForExistence(timeout: 5), "+ glass chip not found")
        add.tap()

        var after = before
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            if let now = glasses(in: tally.label), now != before { after = now; break }
            usleep(250_000)
        }
        XCTAssertEqual(after, before.map { $0 + 1 },
                       "tapping + glass did not advance the tally (before: \(tally.label))")
    }

    /// "3/8 glasses today" → 3, and the row's own wording "…, 6 of 8 glasses" → 6.
    ///
    /// Two shapes because the two labels are written for different readers. The profile chip is
    /// read by eye and says "3/8". The row is a combined accessibility element — read *aloud* —
    /// so its label spells the tally out as "6 of 8 glasses", and a parser that only knows about
    /// slashes returns nil there. It then compares nil to nil and passes whatever the app does;
    /// that is not hypothetical, it is what this parser did until a mutation caught it.
    private func glasses(in label: String) -> Int? {
        let slashForm = label.split(separator: "/")
        if slashForm.count > 1, let n = Int(slashForm[0]) { return n }
        let words = label.split(separator: " ")
        guard let of = words.firstIndex(of: "of"), of > 0 else { return nil }
        return Int(words[of - 1])
    }

    /// The `[+]` on the water habit row itself.
    ///
    /// This is the control people look for on the screen where the habit lives, and the one that
    /// is easy to get wrong: the row is a combined accessibility element (`.combine`), so the
    /// button is only reachable by VoiceOver while it sits *outside* that element.
    ///
    /// Measured, not assumed: nesting the button inside the combine does **not** hide it from
    /// XCUITest. The element tree still reports it, one level deeper, as a child of the row —
    /// because XCUITest walks the underlying view hierarchy, which is not the tree VoiceOver
    /// reads. So querying the button by name proves it exists and is tappable, and nothing about
    /// who can reach it. That is what the containment check below is for: it is the only
    /// assertion here that fails when the button is put back inside the row.
    func testTheWaterRowHasItsOwnLogGlassButton() {
        let app = XCUIApplication()
        app.launchEnvironment["DEBUG_TAB"] = "habits"
        app.launch()

        let row = app.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH 'drink water'")
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 6), "no water habit row found")
        let before = glasses(in: row.label)
        XCTAssertNotNil(before, "could not read a tally out of \"\(row.label)\"")
        let add = app.buttons["log a glass of water"]
        XCTAssertTrue(add.waitForExistence(timeout: 5),
                      "the water row has no glass button of its own")

        // The boundary itself. A sibling is reachable when the row is focused; a child of a
        // combined element is what a finger reaches and VoiceOver does not.
        XCTAssertFalse(row.buttons["log a glass of water"].exists,
                       "the glass button is nested inside the row's combined element")

        // Tapping the row's own control must not be swallowed by the row's toggle underneath it.
        add.tap()

        var after = before
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            if let now = glasses(in: row.label), now != before { after = now; break }
            usleep(250_000)
        }
        XCTAssertEqual(after, before.map { $0 + 1 },
                       "the row's [+] did not advance the tally (was: \(row.label))")
    }
}
