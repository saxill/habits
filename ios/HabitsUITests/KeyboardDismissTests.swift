import XCTest

/// The keyboard has to be escapable.
///
/// Every screen hides the navigation bar, and that takes iOS's own "Done" with it. Profile's body
/// is a plain `ScrollView`, which — unlike a `Form` — does not dismiss the keyboard on drag. So
/// the username field could put the keyboard up with nothing in the app able to take it back
/// down, which is what "the keyboard gets stuck and i cannot remove it" was.
///
/// The keyboard is asserted *present* before anything is dismissed, on purpose. With a hardware
/// keyboard attached the software one never appears, and a test that only checks it is gone
/// afterwards would report success without a keyboard ever having been there — the same
/// false-pass this project keeps having to guard against.
final class KeyboardDismissTests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    private func launchProfile() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["DEBUG_TAB"] = "profile"
        app.launch()
        return app
    }

    /// Focus the username field and confirm a software keyboard is genuinely up.
    @discardableResult
    private func focusUsername(_ app: XCUIApplication) -> XCUIElement {
        let field = app.textFields["username"]
        XCTAssertTrue(field.waitForExistence(timeout: 6), "username field not found")
        field.tap()
        XCTAssertTrue(
            app.keyboards.element.waitForExistence(timeout: 6),
            "no software keyboard appeared, so there was nothing to dismiss and this proves nothing"
        )
        return field
    }

    private func waitForKeyboardToGo(_ app: XCUIApplication, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !app.keyboards.element.exists { return true }
            usleep(200_000)
        }
        return false
    }

    /// The `[done]` key above the keyboard. This is the always-available exit: it does not depend
    /// on the screen being long enough to scroll.
    func testDoneKeyDismissesTheKeyboard() {
        let app = launchProfile()
        focusUsername(app)

        let done = app.buttons["[done]"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "no [done] key above the keyboard")
        done.tap()

        XCTAssertTrue(waitForKeyboardToGo(app), "keyboard stayed up after tapping [done]")
    }

    /// The Return key, which `.submitLabel(.done)` labels "done" — the same word the toolbar key
    /// used to carry, which is why one of them had to be renamed.
    func testReturnKeyDismissesTheKeyboard() {
        let app = launchProfile()
        focusUsername(app)

        let returnKey = app.keyboards.buttons["done"]
        XCTAssertTrue(returnKey.waitForExistence(timeout: 5), "no Return key on the keyboard")
        returnKey.tap()

        XCTAssertTrue(waitForKeyboardToGo(app), "keyboard stayed up after pressing Return")
    }

    /// Dragging the profile body. The affordance people reach for first, and the one the plain
    /// `ScrollView` was silently refusing to provide.
    func testDraggingTheProfileDismissesTheKeyboard() {
        let app = launchProfile()
        focusUsername(app)

        // Vertical, so it is a scroll and not the TabView's horizontal swipe. Started in the
        // upper half on purpose: the keyboard covers the bottom ~40% of the screen, so a drag
        // beginning at 0.75 never reaches the scroll view at all and tests nothing but the
        // keyboard's own inertness — which is how the first version of this reported a failure
        // that was not there.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
        start.press(forDuration: 0.05, thenDragTo: end)

        XCTAssertTrue(waitForKeyboardToGo(app), "keyboard stayed up after dragging the profile")
    }

    /// Tapping the empty background, which is the exit for a drag nobody thinks to make.
    func testTappingTheBackgroundDismissesTheKeyboard() {
        let app = launchProfile()
        focusUsername(app)

        // Above the field, in the preview card — somewhere with no control to steal the tap.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()

        XCTAssertTrue(waitForKeyboardToGo(app), "keyboard stayed up after tapping the background")
    }
}
