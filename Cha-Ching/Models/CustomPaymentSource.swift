import Foundation

struct CustomPaymentSource: Identifiable, Decodable, Hashable {
    let id: String
    let name: String
    let status: Status
    let webhookUrl: URL
    let createdAt: String
    let updatedAt: String

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
        fields.map { field in
            WebhookNotificationField(
                id: field.path,
                path: field.path,
                label: defaultLabel(for: field.path),
                enabled: true
            )
        }
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
}

struct CustomSourceDetail: Decodable {
    let source: CustomPaymentSource
    let sample: WebhookSample?
    let mapping: WebhookFieldMapping?
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
