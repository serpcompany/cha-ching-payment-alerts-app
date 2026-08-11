import Foundation
import Testing
import UserNotifications
@testable import Cha_Ching

struct PaymentNotificationPresentationTests {
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
