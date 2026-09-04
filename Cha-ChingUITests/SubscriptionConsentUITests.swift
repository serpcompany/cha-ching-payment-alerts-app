import XCTest

final class SubscriptionConsentUITests: XCTestCase {
    @MainActor
    func testPurchaseRequiresExplicitConfirmation() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing-subscription-consent",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
        app.launch()

        let purchaseCount = app.staticTexts["subscription-purchase-invocations"]
        let startTrial = app.buttons["Start 7-day free trial"]
        XCTAssertTrue(purchaseCount.waitForExistence(timeout: 5))
        XCTAssertTrue(startTrial.waitForExistence(timeout: 5))
        XCTAssertEqual(purchaseCount.label, "Purchase invocations: 0")

        startTrial.tap()
        let confirmation = app.alerts["Start your 7-day free trial?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 2))
        let disclosure = confirmation.staticTexts.element(boundBy: 1).label
        XCTAssertTrue(disclosure.contains("$14.99"), "Missing localized price: \(disclosure)")
        XCTAssertTrue(disclosure.contains("one year"), "Missing annual period: \(disclosure)")
        XCTAssertTrue(disclosure.contains("renews annually"), "Missing renewal terms: \(disclosure)")
        XCTAssertTrue(disclosure.contains("unless canceled"), "Missing cancellation terms: \(disclosure)")
        XCTAssertEqual(purchaseCount.label, "Purchase invocations: 0")

        app.alerts.buttons["Not now"].tap()
        XCTAssertEqual(purchaseCount.label, "Purchase invocations: 0")

        startTrial.tap()
        app.alerts.buttons["Continue to Apple"].tap()

        let invoked = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "Purchase invocations: 1"),
            object: purchaseCount
        )
        XCTAssertEqual(XCTWaiter.wait(for: [invoked], timeout: 2), .completed)
    }

    @MainActor
    func testReturningSubscriberSeesAnnualPriceAndRenewalTerms() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing-subscription-consent",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
        app.launchEnvironment["SUBSCRIPTION_CONSENT_ACTION"] = "subscribe_again"
        app.launch()

        let subscribeAgain = app.buttons["Subscribe again"]
        XCTAssertTrue(subscribeAgain.waitForExistence(timeout: 5))
        subscribeAgain.tap()

        let confirmation = app.alerts["Confirm annual subscription"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 2))
        let disclosure = confirmation.staticTexts.element(boundBy: 1).label
        XCTAssertTrue(disclosure.contains("$14.99"), "Missing localized price: \(disclosure)")
        XCTAssertTrue(disclosure.contains("one year"), "Missing annual period: \(disclosure)")
        XCTAssertTrue(disclosure.contains("renews annually"), "Missing renewal terms: \(disclosure)")
        XCTAssertTrue(disclosure.contains("unless canceled"), "Missing cancellation terms: \(disclosure)")
    }
}
