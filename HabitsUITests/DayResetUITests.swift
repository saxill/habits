import XCTest

/// The reset button, driven the way a thumb drives it.
///
/// The unit tests cover what a reset does to the store. They cannot cover the part that matters
/// to a person: that the control is reachable, that arming it and clearing it are two taps in the
/// right order, and that the undo chip puts the day back. That path only exists in the view.
final class DayResetUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    /// The "N/M done" line beside the reset chip, read as the number it reports.
    ///
    /// Read rather than assumed: the simulator's store persists between runs, so a hardcoded
    /// expectation would pass once and then fail forever.
    private func doneCount(_ app: XCUIApplication) -> Int? {
        let line = app.staticTexts.matching(
            NSPredicate(format: "label ENDSWITH 'done'")
        ).firstMatch
        guard line.waitForExistence(timeout: 5) else { return nil }
        return line.label.split(separator: "/").first.flatMap { Int($0) }
    }

    /// Waits for the count line to report a specific number, so the test never races the view's
    /// own refresh (the label is refreshed from the store, not optimistically).
    @discardableResult
    private func waitForCount(_ app: XCUIApplication, _ expected: Int) -> Bool {
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            if doneCount(app) == expected { return true }
            usleep(200_000)
        }
        return false
    }

    private func swipeToNextTab(_ app: XCUIApplication, times: Int) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
        for _ in 0..<times {
            start.press(forDuration: 0.05, thenDragTo: end)
        }
    }

    /// Arm, clear, undo — with the day guaranteed dirty first.
    func testResetTodayClearsTheDayAndUndoPutsItBack() {
        let app = XCUIApplication()
        app.launchEnvironment["DEBUG_TAB"] = "profile"
        app.launch()

        // Dirty the day through the one control whose effect is known regardless of what is
        // already ticked: the first glass creates the day's completion.
        let glass = app.buttons["+ glass"]
        XCTAssertTrue(glass.waitForExistence(timeout: 6),
                      "no + glass chip — is there a water habit scheduled today?")
        glass.tap()

        let before = doneCount(app)
        XCTAssertNotNil(before, "could not read the done count in profile")
        XCTAssertGreaterThan(before ?? 0, 0, "the day was not dirty after logging a glass")

        // Arm, then clear. The armed chip carries the count it is about to remove.
        let reset = app.buttons["reset today"]
        XCTAssertTrue(reset.waitForExistence(timeout: 5), "no reset chip")
        reset.tap()

        let clear = app.buttons["clear \(before ?? 0)"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5),
                      "arming the reset did not offer to clear \(before ?? 0)")
        clear.tap()

        XCTAssertTrue(waitForCount(app, 0), "the day still reports work done after a reset")

        // ...and back again.
        let undo = app.buttons["undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5),
                      "no undo chip after a reset — the reset is not recoverable")
        undo.tap()

        XCTAssertTrue(waitForCount(app, before ?? 0),
                      "undo did not restore the \(before ?? 0) completions it took")
    }

    /// The clear is behind a second tap: arming must not clear anything on its own.
    func testArmingTheResetDoesNotClearAnything() {
        let app = XCUIApplication()
        app.launchEnvironment["DEBUG_TAB"] = "profile"
        app.launch()

        let glass = app.buttons["+ glass"]
        XCTAssertTrue(glass.waitForExistence(timeout: 6))
        glass.tap()

        let before = doneCount(app) ?? 0
        XCTAssertGreaterThan(before, 0)

        app.buttons["reset today"].tap()
        XCTAssertTrue(app.buttons["clear \(before)"].waitForExistence(timeout: 5))

        // Nothing is cleared until the second tap — and cancel takes the control back to rest.
        XCTAssertEqual(doneCount(app), before, "arming the reset cleared the day by itself")
        app.buttons["cancel"].tap()
        XCTAssertTrue(app.buttons["reset today"].waitForExistence(timeout: 3),
                      "cancel did not disarm the reset")
        XCTAssertEqual(doneCount(app), before, "the day changed while the reset was cancelled")
    }
}
