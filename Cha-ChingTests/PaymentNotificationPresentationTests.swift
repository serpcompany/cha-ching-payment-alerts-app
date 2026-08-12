import Foundation
import AVFAudio
import Testing
import UserNotifications
@testable import Cha_Ching

struct PaymentNotificationPresentationTests {
    @Test func bundledCashRegisterSoundIsAudible() throws {
        let url = try #require(Bundle.main.url(forResource: "cash-register", withExtension: "caf"))
        let file = try AVAudioFile(forReading: url)
        let buffer = try #require(AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        ))
        try file.read(into: buffer)
        let samples = try #require(buffer.floatChannelData?[0])
        let peak = (0..<Int(buffer.frameLength)).reduce(Float.zero) {
            max($0, abs(samples[$1]))
        }

        #expect(peak >= 0.7)
    }

    @Test func aRealPaymentNotificationTargetsTheDashboardPayment() {
        let destination = PaymentNotificationResponseRouter.destination(
            userInfo: ["saleId": "sale-custom-123"],
            title: "Cha-ching!",
            body: "Amount: $9.00"
        )

        #expect(destination == .dashboardPayment(id: "sale-custom-123"))
    }

    @Test func aConnectionWarningTargetsTheAffectedSource() {
        let destination = PaymentNotificationResponseRouter.destination(
            userInfo: ["connectionHealth": true, "sourceId": "source-quiet"],
            title: "Payment source needs checking",
            body: "SERP Store has not sent a webhook recently."
        )

        #expect(destination == .connectSource(id: "source-quiet"))
    }

    @Test @MainActor func openingANotificationClearsTheAppBadge() async {
        let probe = BadgeClearProbe()

        await withCheckedContinuation { continuation in
            PaymentNotificationResponseRouter.route(
                title: "Cha-ching!",
                body: "Amount: $9.00",
                clearBadge: { probe.wasCleared = true },
                onOpen: { _ in },
                completion: { continuation.resume() }
            )
        }

        #expect(probe.wasCleared)
    }

    @Test func lockScreenResponseReturnsControlToUIKitOnTheMainThread() async {
        let completedOnMainThread = await Task.detached {
            await withCheckedContinuation { continuation in
                PaymentNotificationResponseRouter.route(
                    title: "Cha-ching!",
                    body: "Amount: $9.00",
                    onOpen: { _ in },
                    completion: {
                        continuation.resume(returning: Thread.isMainThread)
                    }
                )
            }
        }.value

        #expect(completedOnMainThread)
    }

    @Test func lockScreenCountdownStartsWithoutAnAcknowledgementStep() {
        let feedback = NotificationTestFeedback.lockScreenScheduled(delaySeconds: 10)

        #expect(feedback.message == "Scheduled. Lock your iPhone now — the test will arrive in about 10 seconds.")
        #expect(feedback.requiresAcknowledgement == false)
    }

    @Test func foregroundDeliveryUsesARealAppleNotificationAndFullDetailsWaitForATap() {
        #expect(PaymentNotificationPresentation.foregroundOptions.contains(.banner))
        #expect(PaymentNotificationPresentation.foregroundOptions.contains(.list))
        #expect(PaymentNotificationPresentation.showsFullDetailsAutomatically == false)
        #expect(PaymentNotificationPresentation.showsFullDetailsAfterTap)
    }

    @Test func foregroundPresentationPreservesEverySelectedStructuredLine() {
        let expectedLines = (1...17).map { "Field \($0): Value \($0)" }

        let notification = ForegroundPaymentNotification(
            title: "Cha-ching!",
            body: expectedLines.joined(separator: "\n")
        )

        #expect(notification.title == "Cha-ching!")
        #expect(notification.lines == expectedLines)
    }

    @Test func paymentNotificationPreferencePersistsAnExplicitOffChoice() throws {
        let suiteName = "PaymentNotificationPresentationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preference = PaymentNotificationPreference(defaults: defaults)

        #expect(preference.isEnabled == false)
        preference.isEnabled = false

        #expect(PaymentNotificationPreference(defaults: defaults).isEnabled == false)
    }
}

@MainActor
private final class BadgeClearProbe {
    var wasCleared = false
}
