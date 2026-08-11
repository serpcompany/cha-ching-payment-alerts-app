import Foundation
import Testing
@testable import Cha_Ching

struct WebhookNotificationDesignerTests {
    @Test func everyDiscoveredFieldBecomesAnEnabledEditableNotificationRow() {
        let fields = [
            WebhookField(path: "/payment/id", value: .string("order_123"), valueType: "string"),
            WebhookField(path: "/payment/amount_minor", value: .number(900), valueType: "number"),
            WebhookField(path: "/source_store", value: .string("serp.store"), valueType: "string")
        ]

        let rows = WebhookNotificationField.defaults(from: fields)

        #expect(rows.map(\.path) == fields.map(\.path))
        #expect(rows.map(\.label) == ["Id", "Amount Minor", "Source Store"])
        #expect(rows.allSatisfy { $0.enabled })
    }

    @Test func toggleRenameAndRemapChoicesAreEncodedInTheMapping() throws {
        let mapping = WebhookFieldMapping(
            paymentIdPath: "/payment/id",
            amountPath: "/payment/amount_minor",
            amountUnit: "minor",
            currencyPath: "/payment/currency",
            notificationFields: [
                WebhookNotificationField(
                    id: "/payment/amount_minor",
                    path: "/payment/total_minor",
                    label: "Paid",
                    enabled: true
                ),
                WebhookNotificationField(
                    id: "/customer/email",
                    path: "/customer/email",
                    label: "Customer",
                    enabled: false
                )
            ]
        )

        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(mapping)) as? [String: Any])
        let rows = try #require(object["notificationFields"] as? [[String: Any]])
        #expect(rows[0]["path"] as? String == "/payment/total_minor")
        #expect(rows[0]["label"] as? String == "Paid")
        #expect(rows[0]["enabled"] as? Bool == true)
        #expect(rows[1]["enabled"] as? Bool == false)
    }
}
