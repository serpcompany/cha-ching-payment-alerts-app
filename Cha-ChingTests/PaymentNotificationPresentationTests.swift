import Foundation
import Testing
@testable import Cha_Ching

struct PaymentNotificationPresentationTests {
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
