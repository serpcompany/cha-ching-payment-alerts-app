import Foundation
import Testing
@testable import Cha_Ching

struct WebhookNotificationDesignerTests {
    @Test func everyDiscoveredFieldBecomesAnEnabledEditableNotificationRow() {
        let fields = [
            WebhookField(path: "/payment/id", value: .string("order_123"), valueType: "string"),
            WebhookField(path: "/payment/amount_minor", value: .number(900), valueType: "number"),
            WebhookField(path: "/source/store", value: .string("serp.store"), valueType: "string")
        ]

        let rows = WebhookNotificationField.defaults(from: fields)

        #expect(rows.map(\.path) == fields.map(\.path))
        #expect(rows.map(\.label) == ["ID", "Amount", "Source Store"])
        #expect(rows.allSatisfy { $0.enabled })
    }

    @Test func businessFieldLabelsPreserveExpectedAcronymsAndMeaning() {
        let fields = [
            WebhookField(path: "/buyer/checkout_country_ip", value: .string("JP"), valueType: "string"),
            WebhookField(path: "/attribution/dub_affiliate_id", value: .string("pn_hasanul"), valueType: "string"),
            WebhookField(path: "/attribution/utm_source", value: .string("dub"), valueType: "string"),
            WebhookField(path: "/payment/occurred_at", value: .string("2026-08-11T08:27:14Z"), valueType: "string")
        ]

        let rows = WebhookNotificationField.defaults(from: fields)

        #expect(rows.map(\.label) == ["Checkout Country (IP)", "Dub Affiliate ID", "UTM Source", "Paid At"])
    }

    @Test func notificationRowsCanBeMovedWithoutChangingTheirChoices() {
        var mapping = WebhookFieldMapping(
            paymentIdPath: "/payment/id",
            amountPath: "/payment/amount_minor",
            amountUnit: "minor",
            currencyPath: "/payment/currency",
            notificationFields: [
                WebhookNotificationField(id: "buyer", path: "/buyer/email", label: "Buyer Email", enabled: true),
                WebhookNotificationField(id: "product", path: "/purchase/product", label: "Product", enabled: false),
                WebhookNotificationField(id: "amount", path: "/payment/amount_minor", label: "Amount", enabled: true)
            ]
        )

        mapping.moveNotificationField(id: "amount", by: -2)

        #expect(mapping.notificationFields.map(\.id) == ["amount", "buyer", "product"])
        #expect(mapping.notificationFields[0].label == "Amount")
        #expect(mapping.notificationFields[0].enabled)
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
