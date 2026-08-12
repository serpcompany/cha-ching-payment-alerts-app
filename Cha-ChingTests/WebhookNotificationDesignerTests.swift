import Foundation
import Testing
@testable import Cha_Ching

struct WebhookNotificationDesignerTests {
    @Test func setupWithoutAnObservedEventPresentsAnHonestWaitingState() throws {
        let source = CustomPaymentSource(
            id: "source-serp-store",
            name: "serp.store",
            status: .setup,
            connectionState: .waiting,
            webhookUrl: try #require(URL(string: "https://api.example.test/webhook/private")),
            createdAt: "2026-08-11 06:00:00",
            updatedAt: "2026-08-11 06:00:00"
        )
        let detail = CustomSourceDetail(source: source, sample: nil, mapping: nil)

        #expect(detail.connectionPresentation.title == "Waiting for first event")
        #expect(detail.connectionPresentation.detail == "Send one representative payment event from your store. Cha-Ching will use it only for setup.")
    }

    @Test func observedStoreEventPresentsItsRealReceiptTimeAndReadyState() throws {
        let source = CustomPaymentSource(
            id: "source-serp-store",
            name: "serp.store",
            status: .setup,
            connectionState: .eventReceived,
            webhookUrl: try #require(URL(string: "https://api.example.test/webhook/private")),
            createdAt: "2026-08-11 06:00:00",
            updatedAt: "2026-08-11 07:06:28"
        )
        let sample = WebhookSample(
            receivedAt: "2026-08-11 07:06:28",
            fields: [WebhookField(path: "/payment/id", value: .string("real-order-123"), valueType: "string")],
            suggestions: nil,
            error: nil
        )
        let detail = CustomSourceDetail(source: source, sample: sample, mapping: nil)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let expectedDate = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 11,
            hour: 7,
            minute: 6,
            second: 28
        )))

        #expect(detail.connectionPresentation.title == "Event received")
        #expect(detail.connectionPresentation.detail == "Ready to configure the fields received from your store.")
        #expect(detail.connectionPresentation.receivedAt == expectedDate)
    }

    @Test func activatedSourcePresentsLivePaymentIntakeInsteadOfSetupData() throws {
        let source = CustomPaymentSource(
            id: "source-serp-store",
            name: "serp.store",
            status: .active,
            connectionState: .active,
            webhookUrl: try #require(URL(string: "https://api.example.test/webhook/private")),
            createdAt: "2026-08-11 06:00:00",
            updatedAt: "2026-08-11 08:00:00"
        )
        let detail = CustomSourceDetail(source: source, sample: nil, mapping: nil)

        #expect(detail.connectionPresentation.title == "Active")
        #expect(detail.connectionPresentation.detail == "New events create Dashboard payments and notifications.")
        #expect(detail.connectionPresentation.receivedAt == nil)
    }

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

    @Test func activationIsAlwaysVisibleButOnlyReadyForTheExactPreviewedChoices() {
        let mapping = WebhookFieldMapping(
            paymentIdPath: "/payment/id",
            amountPath: "/payment/amount_minor",
            amountUnit: "minor",
            currencyPath: "/payment/currency",
            notificationFields: [
                WebhookNotificationField(
                    id: "email",
                    path: "/buyer/email",
                    label: "Buyer Email",
                    enabled: true
                )
            ]
        )
        var changed = mapping
        changed.notificationFields[0].label = "Customer"

        #expect(mapping.isCompleteForNotification)
        #expect(!mapping.isReadyForActivation(after: nil))
        #expect(mapping.isReadyForActivation(after: mapping))
        #expect(!changed.isReadyForActivation(after: mapping))
    }

    @Test func activeNotificationEditsStayDraftUntilTheServerConfirmsSave() {
        let original = WebhookFieldMapping(
            paymentIdPath: "/payment/id",
            amountPath: "/payment/amount_minor",
            amountUnit: "minor",
            currencyPath: "/payment/currency",
            notificationFields: [
                WebhookNotificationField(
                    id: "email",
                    path: "/buyer/email",
                    label: "Buyer Email",
                    enabled: true
                )
            ]
        )
        var editor = ActiveNotificationSettingsDraft(mapping: original)
        editor.notificationFields[0].label = "Customer email"

        #expect(editor.persistedMapping == original)
        #expect(editor.saveConfirmation == nil)

        var accepted = original
        accepted.notificationFields = editor.notificationFields
        editor.accept(accepted)

        #expect(editor.persistedMapping == accepted)
        #expect(editor.notificationFields == accepted.notificationFields)
        #expect(editor.saveConfirmation == "Notification settings saved.")
    }

    @Test func activeNotificationDraftAlwaysHasAPreview() {
        let mapping = WebhookFieldMapping(
            paymentIdPath: "/payment/id",
            amountPath: "/payment/amount_minor",
            amountUnit: "minor",
            currencyPath: "/payment/currency",
            notificationFields: [
                WebhookNotificationField(id: "amount", path: "/payment/amount_minor", label: "Amount", enabled: false),
                WebhookNotificationField(id: "email", path: "/buyer/email", label: "Customer email", enabled: true)
            ]
        )

        #expect(ActiveNotificationSettingsDraft(mapping: mapping).previewBody == "Customer email: Example value")
    }

    @Test func decodedActiveMappingPopulatesDiscoveredAvailableFieldsInTheDraft() throws {
        let response = Data(#"""
        {
          "source": {
            "id": "source-serp",
            "name": "SERP Store",
            "status": "active",
            "connectionState": "active",
            "webhookUrl": "https://api.cha-ching.test/v1/webhooks/custom/private",
            "createdAt": "2026-08-12 00:00:00",
            "updatedAt": "2026-08-12 01:00:00"
          },
          "sample": null,
          "mapping": {
            "paymentIdPath": "/payment/id",
            "amountPath": "/payment/amount_minor",
            "amountUnit": "minor",
            "currencyPath": "/payment/currency",
            "notificationFields": [
              {"id": "amount", "path": "/payment/amount_minor", "label": "Amount", "enabled": true},
              {"id": "observed-dub", "path": "/attribution/dub_affiliate_id", "label": "Dub Affiliate ID", "enabled": true}
            ]
          }
        }
        """#.utf8)

        let detail = try JSONDecoder().decode(CustomSourceDetail.self, from: response)
        let draft = ActiveNotificationSettingsDraft(mapping: try #require(detail.mapping))

        #expect(draft.notificationFields.map(\.label) == ["Amount", "Dub Affiliate ID"])
        #expect(draft.notificationFields.last?.enabled == true)
        #expect(draft.previewBody == "Amount: Example value\nDub Affiliate ID: Example value")
    }
}
