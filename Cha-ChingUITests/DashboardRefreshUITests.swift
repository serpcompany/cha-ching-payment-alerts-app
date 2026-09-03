import XCTest

final class DashboardRefreshUITests: XCTestCase {
    @MainActor
    func testCompletedPullToRefreshRestoresDashboardTopPosition() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing-dashboard-refresh",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
        app.launch()

        let marker = app.descendants(matching: .any)
            .matching(identifier: "dashboard-refresh-marker")
            .firstMatch
        XCTAssertTrue(marker.waitForExistence(timeout: 5))
        XCTAssertEqual(marker.value as? String, "Completed refreshes: 0")
        let restingMinY = marker.frame.minY
        attach(app.screenshot(), name: "Dashboard at rest before refresh")

        let scrollView = app.scrollViews["dashboard-refresh-scroll"]
        XCTAssertTrue(scrollView.waitForExistence(timeout: 2))
        for refreshCount in 1...5 {
            let start = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            let end = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
            start.press(
                forDuration: 0.01,
                thenDragTo: end,
                withVelocity: .fast,
                thenHoldForDuration: 0.5
            )
            XCTAssertTrue(waitForValue(
                "Completed refreshes: \(refreshCount)",
                on: marker,
                timeout: 5
            ))
            XCTAssertEqual(
                marker.frame.minY,
                restingMinY,
                accuracy: 3,
                "Dashboard remained vertically displaced after refresh \(refreshCount) completed"
            )
        }
        attach(app.screenshot(), name: "Dashboard at rest after five refreshes")
    }

    @MainActor
    private func waitForValue(
        _ value: String,
        on element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func attach(_ screenshot: XCUIScreenshot, name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
