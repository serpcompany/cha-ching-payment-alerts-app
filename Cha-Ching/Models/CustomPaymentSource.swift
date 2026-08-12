import Foundation

struct CustomSourceHealth: Decodable, Hashable {
    let status: Status
    let reason: Reason?
    let lastEventReceivedAt: String?
    let lastPaymentReceivedAt: String?
    let expectedEventBy: String?
    let detail: String

    enum Status: String, Decodable {
        case awaitingEvents = "awaiting_events"
        case receiving
        case needsAttention = "needs_attention"
        case paused
    }

    enum Reason: String, Decodable {
        case rejected, quiet
    }

    var statusTitle: String {
        switch status {
        case .awaitingEvents: "No webhook requests yet"
        case .receiving: "Webhook activity received"
        case .needsAttention where reason == .rejected: "Latest webhook request rejected"
        case .needsAttention where reason == .quiet: "No recent webhook activity"
        case .needsAttention: "Webhook activity needs attention"
        case .paused: "Webhook monitoring paused"
        }
    }

    var managementGuidance: String? {
        switch (status, reason) {
        case (.needsAttention, .rejected):
            "Fix the sender payload, then resend it to this webhook URL."
        case (.needsAttention, .quiet):
            "This may be normal when there are no payments. Verify the sending service if you expected activity."
        case (.awaitingEvents, _):
            "Send an event from the sending service to this webhook URL."
        case (.receiving, _), (.paused, _), (.needsAttention, _):
            nil
        }
    }

    var lastEventDate: Date? { Self.date(from: lastEventReceivedAt) }
    var lastPaymentDate: Date? { Self.date(from: lastPaymentReceivedAt) }
    var expectedEventDate: Date? { Self.date(from: expectedEventBy) }
    private static func date(from value: String?) -> Date? {
        guard let value else { return nil }
        let normalized = value.contains("T") ? value : value.replacingOccurrences(of: " ", with: "T") + "Z"
        return try? Date(normalized, strategy: .iso8601)
    }
}

struct CustomPaymentSource: Identifiable, Decodable, Hashable {
    let id: String
    let name: String
    let status: Status
    let connectionState: ConnectionState
    let webhookUrl: URL
    let createdAt: String
    let updatedAt: String
    var health: CustomSourceHealth? = nil

    var displayedStatusTitle: String {
        if status == .active, let health { return health.statusTitle }
        return connectionState.title
    }

    var needsAttention: Bool {
        status == .active && health?.status == .needsAttention
    }

    enum Status: String, Decodable {
        case setup, active, paused

        var title: String {
            switch self {
            case .setup: "Finish setup"
            case .active: "Active"
            case .paused: "Paused"
            }
        }
    }

    enum ConnectionState: String, Decodable {
        case waiting
        case eventReceived = "event_received"
        case active
        case paused

        var title: String {
            switch self {
            case .waiting: "Waiting for first event"
            case .eventReceived: "Event received"
            case .active: "Active"
            case .paused: "Paused"
            }
        }
    }
}

enum WebhookScalar: Decodable, Hashable {
    case string(String)
    case number(Double)
    case boolean(Bool)

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let string = try? value.decode(String.self) { self = .string(string) }
        else if let boolean = try? value.decode(Bool.self) { self = .boolean(boolean) }
        else { self = .number(try value.decode(Double.self)) }
    }

    var displayValue: String {
        switch self {
        case .string(let value): value
        case .number(let value): value.formatted()
        case .boolean(let value): value ? "true" : "false"
        }
    }
}

struct WebhookField: Identifiable, Decodable, Hashable {
    var id: String { path }
    let path: String
    let value: WebhookScalar
    let valueType: String

    var label: String {
        path.split(separator: "/").last.map(String.init) ?? path
    }
}

struct WebhookNotificationField: Identifiable, Codable, Equatable {
    let id: String
    var path: String
    var label: String
    var enabled: Bool

    static func defaults(from fields: [WebhookField]) -> [WebhookNotificationField] {
        fields.enumerated()
            .sorted { left, right in
                let leftPriority = defaultPriority(for: left.element.path)
                let rightPriority = defaultPriority(for: right.element.path)
                return leftPriority == rightPriority
                    ? left.offset < right.offset
                    : leftPriority < rightPriority
            }
            .map { _, field in
                WebhookNotificationField(
                    id: field.path,
                    path: field.path,
                    label: defaultLabel(for: field.path),
                    enabled: true
                )
            }
    }

    private static func defaultPriority(for path: String) -> Int {
        let leaf = path.split(separator: "/").last.map(String.init)?.lowercased() ?? path.lowercased()
        let priorities = [
            "email": 10,
            "buyer_email": 10,
            "checkout_country_ip": 20,
            "product": 30,
            "entitlement": 40,
            "purchase_type": 50,
            "sale_event": 60,
            "amount_minor": 70,
            "amount": 70,
            "dub_affiliate_id": 80,
            "utm_source": 90,
            "utm_medium": 100,
            "utm_campaign": 110,
            "utm_term": 120,
            "utm_content": 130,
            "occurred_at": 140,
            "store": 150,
            "id": 160,
            "currency": 170
        ]
        return priorities[leaf] ?? 1_000
    }

    static func defaultLabel(for path: String) -> String {
        let leaf = path.split(separator: "/").last.map(String.init) ?? path
        let normalized = leaf.lowercased()
        let knownLabels = [
            "id": "ID",
            "email": "Buyer Email",
            "amount_minor": "Amount",
            "store": "Source Store",
            "buyer_email": "Buyer Email",
            "checkout_country_ip": "Checkout Country (IP)",
            "dub_affiliate_id": "Dub Affiliate ID",
            "utm_source": "UTM Source",
            "utm_medium": "UTM Medium",
            "utm_campaign": "UTM Campaign",
            "utm_term": "UTM Term",
            "utm_content": "UTM Content",
            "occurred_at": "Paid At"
        ]
        if let knownLabel = knownLabels[normalized] { return knownLabel }
        return normalized
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .localizedCapitalized
    }
}

struct WebhookFieldMapping: Codable, Equatable {
    var paymentIdPath: String
    var amountPath: String
    var amountUnit: String
    var currencyPath: String?
    var fixedCurrency: String?
    var occurredAtPath: String?
    var productPath: String?
    var planPath: String?
    var saleTypePath: String?
    var notificationFields: [WebhookNotificationField]

    init(
        paymentIdPath: String,
        amountPath: String,
        amountUnit: String,
        currencyPath: String? = nil,
        fixedCurrency: String? = nil,
        occurredAtPath: String? = nil,
        productPath: String? = nil,
        planPath: String? = nil,
        saleTypePath: String? = nil,
        notificationFields: [WebhookNotificationField] = []
    ) {
        self.paymentIdPath = paymentIdPath
        self.amountPath = amountPath
        self.amountUnit = amountUnit
        self.currencyPath = currencyPath
        self.fixedCurrency = fixedCurrency
        self.occurredAtPath = occurredAtPath
        self.productPath = productPath
        self.planPath = planPath
        self.saleTypePath = saleTypePath
        self.notificationFields = notificationFields
    }

    static func inferredAmountUnit(for path: String) -> String {
        let fieldName = path.split(separator: "/").last?.lowercased() ?? path.lowercased()
        return fieldName.contains("minor")
            || fieldName.hasSuffix("cent")
            || fieldName.hasSuffix("cents")
            ? "minor"
            : "major"
    }

    mutating func refreshUntouchedDefaults(from fields: [WebhookField]) {
        let defaults = WebhookNotificationField.defaults(from: fields)
        let defaultPaths = Set(defaults.map(\.path))
        let containsOnlyGeneratedRows = notificationFields.count == defaults.count
            && Set(notificationFields.map(\.path)) == defaultPaths
            && notificationFields.allSatisfy { field in
                field.enabled
                    && field.id == field.path
                    && field.label == WebhookNotificationField.defaultLabel(for: field.path)
            }

        guard notificationFields.isEmpty || containsOnlyGeneratedRows else { return }
        notificationFields = defaults
        if amountUnit == "major", Self.inferredAmountUnit(for: amountPath) == "minor" {
            amountUnit = "minor"
        }
    }

    var isCompleteForNotification: Bool {
        !paymentIdPath.isEmpty
            && !amountPath.isEmpty
            && !(currencyPath ?? "").isEmpty
            && notificationFields.contains(where: \.enabled)
            && notificationFields.allSatisfy {
                !$0.enabled || (
                    !$0.path.isEmpty
                        && !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
    }

    func isReadyForActivation(after previewedMapping: WebhookFieldMapping?) -> Bool {
        isCompleteForNotification && previewedMapping == self
    }

    private enum CodingKeys: String, CodingKey {
        case paymentIdPath, amountPath, amountUnit, currencyPath, fixedCurrency
        case occurredAtPath, productPath, planPath, saleTypePath, notificationFields
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        paymentIdPath = try values.decode(String.self, forKey: .paymentIdPath)
        amountPath = try values.decode(String.self, forKey: .amountPath)
        amountUnit = try values.decode(String.self, forKey: .amountUnit)
        currencyPath = try values.decodeIfPresent(String.self, forKey: .currencyPath)
        fixedCurrency = try values.decodeIfPresent(String.self, forKey: .fixedCurrency)
        occurredAtPath = try values.decodeIfPresent(String.self, forKey: .occurredAtPath)
        productPath = try values.decodeIfPresent(String.self, forKey: .productPath)
        planPath = try values.decodeIfPresent(String.self, forKey: .planPath)
        saleTypePath = try values.decodeIfPresent(String.self, forKey: .saleTypePath)
        notificationFields = try values.decodeIfPresent(
            [WebhookNotificationField].self,
            forKey: .notificationFields
        ) ?? []
    }

    mutating func moveNotificationField(id: String, by offset: Int) {
        guard let oldIndex = notificationFields.firstIndex(where: { $0.id == id }) else { return }
        let newIndex = min(max(oldIndex + offset, notificationFields.startIndex), notificationFields.index(before: notificationFields.endIndex))
        guard oldIndex != newIndex else { return }
        let field = notificationFields.remove(at: oldIndex)
        notificationFields.insert(field, at: newIndex)
    }
}

struct ActiveNotificationSettingsDraft: Equatable {
    private(set) var persistedMapping: WebhookFieldMapping
    var notificationFields: [WebhookNotificationField]
    private(set) var saveConfirmation: String?

    init(mapping: WebhookFieldMapping) {
        persistedMapping = mapping
        notificationFields = mapping.notificationFields
    }

    var previewBody: String {
        let body = notificationFields
            .filter(\.enabled)
            .map { "\($0.label): Example value" }
            .joined(separator: "\n")
        return body.isEmpty ? "Payment received." : body
    }

    mutating func accept(_ mapping: WebhookFieldMapping) {
        persistedMapping = mapping
        notificationFields = mapping.notificationFields
        saveConfirmation = "Notification settings saved."
    }
}

struct NotificationTestFeedback: Equatable {
    let message: String
    let requiresAcknowledgement: Bool

    static func lockScreenScheduled(delaySeconds: Int) -> NotificationTestFeedback {
        NotificationTestFeedback(
            message: "Scheduled. Lock your iPhone now — the test will arrive in about \(delaySeconds) seconds.",
            requiresAcknowledgement: false
        )
    }
}

struct WebhookMappingSuggestions: Decodable {
    let paymentIdPath: String?
    let amountPath: String?
    let currencyPath: String?
    let occurredAtPath: String?
    let productPath: String?
    let planPath: String?
    let saleTypePath: String?
}

struct WebhookSample: Decodable {
    let receivedAt: String?
    let fields: [WebhookField]?
    let suggestions: WebhookMappingSuggestions?
    let error: String?

    var receivedDate: Date? {
        guard let receivedAt else { return nil }
        let iso8601 = receivedAt.replacingOccurrences(of: " ", with: "T") + "Z"
        return try? Date(iso8601, strategy: .iso8601)
    }
}

struct CustomSourceDetail: Decodable {
    let source: CustomPaymentSource
    let sample: WebhookSample?
    let mapping: WebhookFieldMapping?

    var connectionPresentation: CustomSourceConnectionPresentation {
        switch source.connectionState {
        case .active:
            return CustomSourceConnectionPresentation(
                title: "Active",
                detail: "New events create Dashboard payments and notifications.",
                receivedAt: nil
            )
        case .paused:
            return CustomSourceConnectionPresentation(
                title: "Paused",
                detail: "New events are ignored until you resume this source.",
                receivedAt: nil
            )
        case .eventReceived:
            return CustomSourceConnectionPresentation(
                title: "Event received",
                detail: "Ready to configure the fields received from your store.",
                receivedAt: sample?.receivedDate
            )
        case .waiting:
            return CustomSourceConnectionPresentation(
                title: "Waiting for first event",
                detail: "Send one representative payment event from your store. Cha-Ching will use it only for setup.",
                receivedAt: nil
            )
        }
    }
}

struct CustomSourceConnectionPresentation: Equatable {
    let title: String
    let detail: String
    let receivedAt: Date?
}

struct CustomPaymentPreview: Decodable {
    let paymentId: String
    let amountMinor: Int
    let currency: String
    let occurredAt: Date
    let productLabel: String
    let plan: String?
    let saleType: String?
    let isSubscription: Bool
    let notificationFields: [WebhookNotificationFieldPreview]?
    let notificationBody: String?

    var formattedAmount: String {
        let zeroDecimal = ["BIF", "CLP", "DJF", "GNF", "JPY", "KMF", "KRW", "MGA", "PYG", "RWF", "UGX", "VND", "VUV", "XAF", "XOF", "XPF"]
        let threeDecimal = ["BHD", "JOD", "KWD", "OMR", "TND"]
        let exponent = zeroDecimal.contains(currency) ? 0 : threeDecimal.contains(currency) ? 3 : 2
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        return formatter.string(from: NSNumber(value: Double(amountMinor) / pow(10, Double(exponent))))
            ?? "\(amountMinor) \(currency)"
    }
}

struct WebhookNotificationFieldPreview: Identifiable, Decodable, Hashable {
    let id: String
    let path: String
    let label: String
    let enabled: Bool
    let value: String
}
