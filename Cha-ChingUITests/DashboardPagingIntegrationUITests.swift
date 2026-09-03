import XCTest

final class DashboardPagingIntegrationUITests: XCTestCase {
    @MainActor
    func testDelayedSuccessAndFailureKeepDashboardDayCoherent() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing-dashboard-paging",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
        app.launch()

        let selectedOffset = app.staticTexts["dashboard-paging-selected-offset"]
        XCTAssertTrue(selectedOffset.waitForExistence(timeout: 5))
        XCTAssertTrue(card(in: app, id: 0).waitForExistence(timeout: 5))
        XCTAssertEqual(selectedOffset.label, "Dashboard day offset: 0")
        XCTAssertEqual(card(in: app, id: 0).value as? String, "Loaded")
        XCTAssertTrue(app.navigationBars["Today"].exists)

        card(in: app, id: 0).swipeRight(velocity: .slow)
        wait(for: selectedOffset, toHaveLabel: "Dashboard day offset: 1")
        XCTAssertTrue(card(in: app, id: 1).waitForExistence(timeout: 3))
        XCTAssertEqual(card(in: app, id: 1).value as? String, "Loaded")
        XCTAssertTrue(app.navigationBars["Wed, Sep 2"].exists)

        card(in: app, id: 1).swipeRight(velocity: .slow)
        XCTAssertTrue(app.staticTexts["Dashboard couldn't refresh."].waitForExistence(timeout: 4))
        wait(for: selectedOffset, toHaveLabel: "Dashboard day offset: 1")
        XCTAssertTrue(card(in: app, id: 1).waitForExistence(timeout: 3))
        XCTAssertEqual(card(in: app, id: 1).value as? String, "Loaded")
        XCTAssertTrue(app.navigationBars["Wed, Sep 2"].exists)
    }

    @MainActor
    private func card(in app: XCUIApplication, id: Int) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "daily-summary-card.\(id)")
            .firstMatch
    }

    @MainActor
    private func wait(for element: XCUIElement, toHaveLabel label: String) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", label),
            object: element
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 4), .completed)
    }
}
