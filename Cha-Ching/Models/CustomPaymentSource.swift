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
