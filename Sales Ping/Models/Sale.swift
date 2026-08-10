import SwiftUI

enum Processor: String, CaseIterable, Identifiable, Codable {
    case stripe, paypal, gumroad

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stripe: return "Stripe"
        case .paypal: return "PayPal"
        case .gumroad: return "Gumroad"
        }
    }

    var symbol: String {
        switch self {
        case .stripe: return "creditcard.fill"
        case .paypal: return "p.circle.fill"
        case .gumroad: return "bag.fill"
        }
    }

    var color: Color {
        switch self {
        case .stripe: return Theme.adaptive(light: (0.39, 0.36, 0.94), dark: (0.55, 0.53, 1.0))
        case .paypal: return Theme.adaptive(light: (0.0, 0.44, 0.75), dark: (0.35, 0.68, 1.0))
        case .gumroad: return Theme.adaptive(light: (0.90, 0.35, 0.55), dark: (1.0, 0.52, 0.70))
        }
    }
}

struct Sale: Identifiable, Hashable {
    let id = UUID()
    var product: String
    var customer: String
    var amount: Double
    var currency: String = "USD"
    var processor: Processor
    var date: Date
    var isSubscription: Bool = false
    var country: String

    var formattedAmount: String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currency
        f.maximumFractionDigits = amount.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
        return f.string(from: NSNumber(value: amount)) ?? "$\(amount)"
    }
}

struct ProcessorConnection: Identifiable {
    var id: String { processor.rawValue }
    var processor: Processor
    var isConnected: Bool
    var accountName: String?
}
