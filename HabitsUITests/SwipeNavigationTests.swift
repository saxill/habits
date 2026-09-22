import XCTest

/// The two sideways gestures, driven by real touches.
///
/// Nothing else can: `simctl` has no input injection, `devicectl` has none either, and the
/// simulator cannot be driven from the shell here (no `cliclick`, no `idb`, no Quartz). So a
/// UI test is the only place these get verified at all rather than compiled and hoped for.
///
/// Assertions go through `screen-command` — the `$ daily` / `$ stats` / `$ appearance` word in
/// each screen's header. It is the one element guaranteed to differ between screens, and it is
/// read only from a hittable match, because TabView keeps the unselected tabs in the hierarchy
/// where `exists` would happily report a screen nobody is looking at.
final class SwipeNavigationTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(screen: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        if let screen { app.launchEnvironment["DEBUG_SCREEN"] = screen }
        app.launch()
        return app
    }

    /// The header command of whichever screen is actually on screen.
    private func visibleCommand(_ app: XCUIApplication) -> String? {
        let matches = app.staticTexts.matching(identifier: "screen-command")
        for index in 0..<matches.count {
            let element = matches.element(boundBy: index)
            if element.exists && element.isHittable { return element.label }
        }
        return nil
    }

    private func assertScreen(_ app: XCUIApplication, is command: String,
                              file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if visibleCommand(app) == command { return }
            usleep(100_000)
        }
        XCTFail("expected the \(command) screen, saw \(visibleCommand(app) ?? "nothing")",
                file: file, line: line)
    }

    /// A horizontal drag across the middle of the screen — clear of the tab bar, and clear of
    /// the header.
    private func swipe(_ app: XCUIApplication, fromRight: Bool) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: fromRight ? 0.85 : 0.15,
                                                                  dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: fromRight ? 0.15 : 0.85,
                                                                dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    // MARK: - Tabs

    /// The chain Sahil asked for: swipe towards the left and the tabs advance
    /// habits → stats → profile, and back again.
    func testSwipeStepsThroughTabsBothWays() {
        let app = launch()
        assertScreen(app, is: "daily")

        swipe(app, fromRight: true)
        assertScreen(app, is: "stats")

        swipe(app, fromRight: true)
        assertScreen(app, is: "appearance")

        // the strip is clamped, not wrapped: past the last tab nothing moves
        swipe(app, fromRight: true)
        assertScreen(app, is: "appearance")

        swipe(app, fromRight: false)
        assertScreen(app, is: "stats")

        swipe(app, fromRight: false)
        assertScreen(app, is: "daily")

        // ...and past the first one, likewise
        swipe(app, fromRight: false)
        assertScreen(app, is: "daily")
    }

    /// A vertical drag is a scroll, not a tab change. Every screen is a long vertical
    /// scroller, so a loose horizontal test here would make the whole app feel broken.
    func testVerticalDragDoesNotChangeTab() {
        let app = launch()
        assertScreen(app, is: "daily")

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        start.press(forDuration: 0.05, thenDragTo: end)

        assertScreen(app, is: "daily")
    }

    /// The chip row on the stats tab scrolls sideways too, so it is declared off-limits to the
    /// tab swipe. Without that opt-out this drag would scroll the chips *and* land on profile —
    /// which is exactly the kind of double-action that reads as the app being broken.
    func testHorizontalDragOnChipRowScrollsWithoutChangingTab() {
        let app = XCUIApplication()
        app.launchEnvironment["DEBUG_TAB"] = "stats"
        app.launchEnvironment["DEBUG_SEGMENT"] = "habits"
        app.launch()
        assertScreen(app, is: "stats")

        let chips = app.descendants(matching: .any).matching(identifier: "habit-chips").firstMatch
        XCTAssertTrue(chips.waitForExistence(timeout: 3), "chip row not found")
        XCTAssertTrue(chips.isHittable, "chip row is not on screen")

        let start = chips.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        let end = chips.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)

        assertScreen(app, is: "stats")
    }

    // MARK: - Back out of a pushed screen

    /// Rightward from the *middle* of the screen leaves the achievements screen.
    ///
    /// The start point is the whole test. The system's interactive pop only arms within about
    /// 20pt of the left edge, so an earlier version of this test — which dragged from 2pt in —
    /// passed while the gesture was useless in a hand: no finger starts that close by accident,
    /// and anything further in did nothing at all. A drag from the centre is the honest test.
    func testSwipeRightFromMiddleGoesBackFromAchievements() {
        let app = launch(screen: "achievements")
        assertScreen(app, is: "achievements")

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)

        assertScreen(app, is: "appearance")
    }

    /// ...and a leftward drag there stays put: forward is not a gesture this screen has.
    func testSwipeLeftOnAchievementsDoesNotGoBack() {
        let app = launch(screen: "achievements")
        assertScreen(app, is: "achievements")

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)

        assertScreen(app, is: "achievements")
    }

    /// A short drag that does not commit snaps back instead of going back — otherwise every
    /// small sideways twitch on the screen would leave it.
    func testShortDragDoesNotLeaveAchievements() {
        let app = launch(screen: "achievements")
        assertScreen(app, is: "achievements")

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.42, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)

        assertScreen(app, is: "achievements")
    }
}
