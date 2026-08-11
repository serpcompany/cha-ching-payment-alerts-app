import Foundation
import Testing
@testable import Cha_Ching

struct WebhookNotificationDesignerTests {
    @Test func amountUnitFollowsTheObservedAmountFieldName() {
        #expect(WebhookFieldMapping.inferredAmountUnit(for: "/payment/amount_minor") == "minor")
        #expect(WebhookFieldMapping.inferredAmountUnit(for: "/order/total_cents") == "minor")
        #expect(WebhookFieldMapping.inferredAmountUnit(for: "/order/total") == "major")
    }

    @Test func everyDiscoveredFieldBecomesAnEnabledEditableNotificationRow() {
        let fields = [
            WebhookField(path: "/payment/id", value: .string("order_123"), valueType: "string"),
            WebhookField(path: "/payment/amount_minor", value: .number(900), valueType: "number"),
            WebhookField(path: "/source/store", value: .string("serp.store"), valueType: "string")
        ]

        let rows = WebhookNotificationField.defaults(from: fields)

        #expect(Set(rows.map(\.path)) == Set(fields.map(\.path)))
        #expect(Dictionary(uniqueKeysWithValues: rows.map { ($0.path, $0.label) }) == [
            "/payment/id": "ID",
            "/payment/amount_minor": "Amount",
            "/source/store": "Source Store"
        ])
        #expect(rows.allSatisfy { $0.enabled })
    }

    @Test func knownBusinessFieldsStartInTheStandardNotificationOrder() {
        let fields = [
            WebhookField(path: "/attribution/utm_campaign", value: .string("launch"), valueType: "string"),
            WebhookField(path: "/payment/id", value: .string("order_123"), valueType: "string"),
            WebhookField(path: "/purchase/product", value: .string("Downloader"), valueType: "string"),
            WebhookField(path: "/buyer/email", value: .string("buyer@example.com"), valueType: "string"),
            WebhookField(path: "/payment/amount_minor", value: .number(900), valueType: "number"),
            WebhookField(path: "/custom/note", value: .string("Keep me"), valueType: "string")
        ]

        let rows = WebhookNotificationField.defaults(from: fields)

        #expect(rows.map(\.path) == [
            "/buyer/email",
            "/purchase/product",
            "/payment/amount_minor",
            "/attribution/utm_campaign",
            "/payment/id",
            "/custom/note"
        ])
    }

    @Test func oldUntouchedSetupDefaultsReceiveTheImprovedOrderAndAmountUnit() {
        let fields = [
            WebhookField(path: "/payment/id", value: .string("order_123"), valueType: "string"),
            WebhookField(path: "/payment/amount_minor", value: .number(900), valueType: "number"),
            WebhookField(path: "/buyer/email", value: .string("buyer@example.com"), valueType: "string")
        ]
        var mapping = WebhookFieldMapping(
            paymentIdPath: "/payment/id",
            amountPath: "/payment/amount_minor",
            amountUnit: "major",
            currencyPath: "/payment/currency",
            notificationFields: fields.map { field in
                WebhookNotificationField(
                    id: field.path,
                    path: field.path,
                    label: WebhookNotificationField.defaultLabel(for: field.path),
                    enabled: true
                )
            }
        )

        mapping.refreshUntouchedDefaults(from: fields)

        #expect(mapping.amountUnit == "minor")
        #expect(mapping.notificationFields.map(\.path) == [
            "/buyer/email",
            "/payment/amount_minor",
            "/payment/id"
        ])
    }

    @Test func improvedDefaultsDoNotReplaceAUsersCustomization() {
        let fields = [
            WebhookField(path: "/payment/id", value: .string("order_123"), valueType: "string"),
            WebhookField(path: "/buyer/email", value: .string("buyer@example.com"), valueType: "string")
        ]
        var mapping = WebhookFieldMapping(
            paymentIdPath: "/payment/id",
            amountPath: "/payment/amount_minor",
            amountUnit: "major",
            currencyPath: "/payment/currency",
            notificationFields: [
                WebhookNotificationField(
                    id: "/payment/id",
                    path: "/payment/id",
                    label: "Receipt",
                    enabled: true
                ),
                WebhookNotificationField(
                    id: "/buyer/email",
                    path: "/buyer/email",
                    label: "Buyer Email",
                    enabled: true
                )
            ]
        )

        mapping.refreshUntouchedDefaults(from: fields)

        #expect(mapping.notificationFields.map(\.label) == ["Receipt", "Buyer Email"])
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
