import XCTest
import Vision

final class DailySummaryCarouselUITests: XCTestCase {
    @MainActor
    func testOneHorizontalSwipeSelectsExactlyOneCalendarDay() throws {
        let app = launchPagingFixture()
        let selectedOffset = app.staticTexts["summary-paging-selected-offset"]
        XCTAssertTrue(selectedOffset.waitForExistence(timeout: 5))
        XCTAssertEqual(selectedOffset.label, "Day offset: 0")

        card(in: app, id: 0).swipeRight(velocity: .slow)

        wait(for: selectedOffset, toHaveLabel: "Day offset: 1")
        XCTAssertEqual(selectedOffset.label, "Day offset: 1")
        retainScreenshot(of: app, named: "one-swipe-offset-1")
    }

    @MainActor
    func testDebouncedFallbackSelectsExactlyOneCalendarDay() throws {
        let app = launchPagingFixture(forceDebouncedCommit: true)
        let selectedOffset = app.staticTexts["summary-paging-selected-offset"]
        XCTAssertTrue(selectedOffset.waitForExistence(timeout: 5))

        card(in: app, id: 0).swipeRight(velocity: .slow)

        wait(for: selectedOffset, toHaveLabel: "Day offset: 1")
        XCTAssertTrue(card(in: app, id: 1).waitForExistence(timeout: 2))
        waitForPagingToSettle()
        XCTAssertEqual(selectedOffset.label, "Day offset: 1")
    }

    @MainActor
    func testTodayIsTheForwardPagingBoundary() throws {
        let app = launchPagingFixture()
        let selectedOffset = app.staticTexts["summary-paging-selected-offset"]
        XCTAssertTrue(selectedOffset.waitForExistence(timeout: 5))

        card(in: app, id: 0).swipeLeft(velocity: .slow)
        waitForPagingToSettle()

        XCTAssertEqual(selectedOffset.label, "Day offset: 0")
        XCTAssertFalse(card(in: app, id: -1).exists)
    }

    @MainActor
    func testRapidAlternatingSwipesStayMonotonicOneDayAtATime() throws {
        let app = launchPagingFixture()
        let selectedOffset = app.staticTexts["summary-paging-selected-offset"]
        XCTAssertTrue(selectedOffset.waitForExistence(timeout: 5))

        for (current, expected, direction) in [
            (0, 1, CGVector(dx: 1, dy: 0)),
            (1, 0, CGVector(dx: -1, dy: 0)),
            (0, 1, CGVector(dx: 1, dy: 0)),
            (1, 0, CGVector(dx: -1, dy: 0)),
        ] {
            XCTAssertEqual(selectedOffset.label, "Day offset: \(current)")
            let currentCard = card(in: app, id: current)
            let start = currentCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let end = currentCard.coordinate(withNormalizedOffset: CGVector(
                dx: direction.dx > 0 ? 0.9 : 0.1,
                dy: 0.5
            ))
            start.press(forDuration: 0.01, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
            wait(for: selectedOffset, toHaveLabel: "Day offset: \(expected)")
            XCTAssertTrue(card(in: app, id: expected).waitForExistence(timeout: 2))
            XCTAssertEqual(selectedOffset.label, "Day offset: \(expected)")
        }
        retainScreenshot(of: app, named: "rapid-alternating-back-at-today")
    }

    @MainActor
    func testOverlappingFallbackSwipesCannotCascadeAcrossDays() throws {
        let app = launchPagingFixture(forceDebouncedCommit: true)
        let selectedOffset = app.staticTexts["summary-paging-selected-offset"]
        let selectionHistory = app.staticTexts["summary-paging-selection-history"]
        XCTAssertTrue(selectedOffset.waitForExistence(timeout: 5))
        XCTAssertTrue(selectionHistory.waitForExistence(timeout: 2))

        let left = app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.20))
        let right = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.20))
        for (start, end) in [(left, right), (right, left), (left, right), (right, left)] {
            start.press(forDuration: 0.01, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
        }
        waitForPagingToSettle()

        let offsets = selectionHistory.label.split(separator: ",").compactMap { Int($0) }
        XCTAssertFalse(offsets.isEmpty)
        XCTAssertTrue(offsets.allSatisfy { (0...1).contains($0) }, "Unexpected history: \(offsets)")
        XCTAssertTrue(
            zip(offsets, offsets.dropFirst()).allSatisfy { abs($0 - $1) <= 1 },
            "Every committed gesture must move by at most one day: \(offsets)"
        )
        XCTAssertTrue(
            ["Day offset: 0", "Day offset: 1"].contains(selectedOffset.label),
            "Overlapping input must be ignored or resolve one day at most; got \(selectedOffset.label)"
        )
    }

    @MainActor
    func testVerticalPullAndScrollDoNotChangeTheSelectedDay() throws {
        let app = launchPagingFixture()
        let selectedOffset = app.staticTexts["summary-paging-selected-offset"]
        XCTAssertTrue(selectedOffset.waitForExistence(timeout: 5))
        XCTAssertEqual(selectedOffset.label, "Day offset: 0")

        let todayCard = card(in: app, id: 0)
        todayCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            .press(
                forDuration: 0.05,
                thenDragTo: todayCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)),
                withVelocity: .slow,
                thenHoldForDuration: 0
            )
        app.swipeUp(velocity: .fast)
        waitForPagingToSettle()

        XCTAssertEqual(selectedOffset.label, "Day offset: 0")
        retainScreenshot(of: app, named: "vertical-gestures-still-today")
    }

    @MainActor
    func testSummaryCardsUseOneResponsiveGeometryForLoadingShortAndLongContent() throws {
        var app = launchSummaryCardFixture(initialPage: 1)
        let shortCard = card(in: app, id: 1)
        XCTAssertTrue(shortCard.waitForExistence(timeout: 5))
        let shortFrame = shortCard.frame

        app = launchSummaryCardFixture(initialPage: 2)
        let longCard = card(in: app, id: 2)
        XCTAssertTrue(longCard.waitForExistence(timeout: 5))
        let longFrame = longCard.frame

        app = launchSummaryCardFixture(initialPage: 0)
        let loadingCard = card(in: app, id: 0)
        XCTAssertTrue(loadingCard.waitForExistence(timeout: 5))
        let loadingFrame = loadingCard.frame

        for frame in [loadingFrame, longFrame] {
            XCTAssertEqual(frame.width, shortFrame.width, accuracy: 1)
            XCTAssertEqual(frame.height, shortFrame.height, accuracy: 1)
        }

        let widthRatio = shortFrame.width / app.frame.width
        XCTAssertEqual(widthRatio, 0.92, accuracy: 0.03)
        XCTAssertGreaterThanOrEqual(shortFrame.height, 100)
    }

    @MainActor
    func testSummaryCardShowsEveryCharacterOfLongAmounts() throws {
        let app = launchSummaryCardFixture(initialPage: 2)
        let longCard = card(in: app, id: 2)
        XCTAssertTrue(longCard.waitForExistence(timeout: 5))

        let screenshot = app.screenshot()
        let croppedImage = try crop(screenshot.image, to: longCard.frame, in: app.frame)
        let recognizedText = try recognizeText(in: croppedImage)
        let normalizedText = recognizedText.filter { !$0.isWhitespace }

        for literal in ["$1,234,567.89", "1,234,567"] {
            XCTAssertTrue(
                normalizedText.contains(literal),
                "Expected fully rendered literal \(literal) in Vision output: \(recognizedText)"
            )
        }
        XCTAssertFalse(
            recognizedText.contains("Avg. $"),
            "Average payment must not appear in the two-metric summary: \(recognizedText)"
        )
        XCTAssertFalse(
            recognizedText.contains("$987,654.32"),
            "Average payment value must not appear in the two-metric summary: \(recognizedText)"
        )
        XCTAssertFalse(recognizedText.contains("…"), "Unexpected ellipsis in Vision output: \(recognizedText)")
        XCTAssertNil(
            recognizedText.range(of: #"\.{3,}"#, options: .regularExpression),
            "Unexpected dot truncation in Vision output: \(recognizedText)"
        )

        let grossMetric = app.descendants(matching: .any)
            .matching(identifier: "daily-summary-metric.2.gross-volume")
            .firstMatch
        let paymentsMetric = app.descendants(matching: .any)
            .matching(identifier: "daily-summary-metric.2.payments")
            .firstMatch
        XCTAssertTrue(grossMetric.waitForExistence(timeout: 2))
        XCTAssertTrue(paymentsMetric.waitForExistence(timeout: 2))
        XCTAssertEqual(grossMetric.frame.width, paymentsMetric.frame.width, accuracy: 1)
        XCTAssertEqual(
            (grossMetric.frame.midX + paymentsMetric.frame.midX) / 2,
            longCard.frame.midX,
            accuracy: 1
        )
        XCTAssertEqual(
            longCard.frame.midX - grossMetric.frame.midX,
            paymentsMetric.frame.midX - longCard.frame.midX,
            accuracy: 1
        )

        let accessibilityText = [
            grossMetric.label,
            grossMetric.value as? String ?? "",
            paymentsMetric.label,
            paymentsMetric.value as? String ?? "",
        ]
            .joined(separator: " ")
        XCTAssertTrue(accessibilityText.contains("Gross volume"))
        XCTAssertTrue(accessibilityText.contains("Payments"))
        XCTAssertFalse(accessibilityText.contains("Avg."))
        XCTAssertFalse(accessibilityText.contains("$987,654.32"))
    }

    @MainActor
    private func launchSummaryCardFixture(initialPage: Int) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing-summary-cards",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL",
        ]
        app.launchEnvironment["SUMMARY_CARD_INITIAL_PAGE"] = String(initialPage)
        app.launch()
        return app
    }

    @MainActor
    private func launchPagingFixture(forceDebouncedCommit: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing-summary-paging",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
        if forceDebouncedCommit {
            app.launchArguments.append("-ui-testing-summary-paging-debounced")
        }
        app.launch()
        return app
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
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 3), .completed)
    }

    private func waitForPagingToSettle() {
        let expectation = XCTestExpectation(description: "Paging remains stable after deceleration")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { expectation.fulfill() }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 2), .completed)
    }

    @MainActor
    private func retainScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func crop(_ image: UIImage, to frame: CGRect, in appFrame: CGRect) throws -> CGImage {
        let cgImage = try XCTUnwrap(image.cgImage)
        let scaleX = CGFloat(cgImage.width) / appFrame.width
        let scaleY = CGFloat(cgImage.height) / appFrame.height
        let pixelFrame = CGRect(
            x: frame.minX * scaleX,
            y: frame.minY * scaleY,
            width: frame.width * scaleX,
            height: frame.height * scaleY
        ).integral
        return try XCTUnwrap(cgImage.cropping(to: pixelFrame))
    }

    private func recognizeText(in image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
}
