import XCTest
import Vision

final class DailySummaryCarouselUITests: XCTestCase {
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

        for literal in ["$1,234,567.89", "1,234,567", "$987,654.32"] {
            XCTAssertTrue(
                normalizedText.contains(literal),
                "Expected fully rendered literal \(literal) in Vision output: \(recognizedText)"
            )
        }
        XCTAssertFalse(recognizedText.contains("…"), "Unexpected ellipsis in Vision output: \(recognizedText)")
        XCTAssertNil(
            recognizedText.range(of: #"\.{3,}"#, options: .regularExpression),
            "Unexpected dot truncation in Vision output: \(recognizedText)"
        )
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
    private func card(in app: XCUIApplication, id: Int) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "daily-summary-card.\(id)")
            .firstMatch
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
