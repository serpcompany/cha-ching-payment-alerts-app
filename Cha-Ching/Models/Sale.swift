import SwiftUI

enum Processor: String, CaseIterable, Identifiable, Codable {
    case stripe, paypal, lemonsqueezy, gumroad, dodoPayments = "dodo_payments", whop, polar

    var id: String { rawValue }

    static let mvpProviders: [Processor] = [.stripe, .paypal]

    var title: String {
        switch self {
        case .stripe: return "Stripe"
        case .paypal: return "PayPal"
        case .lemonsqueezy: return "Lemon Squeezy"
        case .gumroad: return "Gumroad"
        case .dodoPayments: return "Dodo Payments"
        case .whop: return "Whop"
        case .polar: return "Polar"
        }
    }

    var symbol: String {
        switch self {
        case .stripe: return "creditcard.fill"
        case .paypal: return "p.circle.fill"
        case .lemonsqueezy: return "cup.and.saucer.fill"
        case .gumroad: return "bag.fill"
        case .dodoPayments: return "circle.hexagongrid.fill"
        case .whop: return "sparkles.square.filled.on.square"
        case .polar: return "moon.stars.fill"
        }
    }

    var color: Color {
        switch self {
        case .stripe: return Theme.adaptive(light: (0.39, 0.36, 0.94), dark: (0.55, 0.53, 1.0))
        case .paypal: return Theme.adaptive(light: (0.0, 0.44, 0.75), dark: (0.35, 0.68, 1.0))
        case .lemonsqueezy: return Theme.adaptive(light: (0.95, 0.71, 0.10), dark: (1.0, 0.80, 0.30))
        case .gumroad: return Theme.adaptive(light: (0.90, 0.35, 0.55), dark: (1.0, 0.52, 0.70))
        case .dodoPayments: return Theme.adaptive(light: (0.15, 0.55, 0.55), dark: (0.30, 0.75, 0.75))
        case .whop: return Theme.adaptive(light: (0.10, 0.75, 0.45), dark: (0.25, 0.90, 0.60))
        case .polar: return Theme.adaptive(light: (0.20, 0.30, 0.55), dark: (0.55, 0.65, 1.0))
        }
    }

    /// How a user grants Cha-Ching access at the provider.
    var setupHint: String {
        switch self {
        case .stripe: return "Install Cha-Ching from Stripe's permission screen. It can read successful payment events, but it cannot create or change payments."
        case .paypal: return "Sign in to PayPal and choose the account you want Cha-Ching to link."
        case .lemonsqueezy: return "Paste an API key from Lemon Squeezy Settings → API, plus your webhook signing secret."
        case .gumroad: return "Paste your access token from Gumroad Settings → Advanced."
        case .dodoPayments: return "Paste your secret API key from the Dodo Payments dashboard."
        case .whop: return "Paste your API key from the Whop developer dashboard."
        case .polar: return "Paste an access token from Polar Settings → Developers."
        }
    }

    var needsWebhookSecret: Bool {
        switch self {
        case .stripe, .lemonsqueezy, .whop, .polar, .dodoPayments: return true
        case .paypal, .gumroad: return false
        }
    }
}

struct Sale: Identifiable, Hashable {
    let id: String
    let product: String
    let amountMinor: Int
    let currency: String
    let processor: Processor
    let date: Date
    let isSubscription: Bool
    let countryCode: String?

    var amount: Double {
        Double(amountMinor) / pow(10, Double(currencyExponent))
    }

    var customer: String { "Verified by \(processor.title)" }

    var country: String {
        guard let countryCode else { return "🌎" }
        return countryCode.uppercased().unicodeScalars.compactMap {
            UnicodeScalar(127397 + $0.value).map(String.init)
        }.joined()
    }

    private var currencyExponent: Int {
        let zeroDecimal = ["BIF", "CLP", "DJF", "GNF", "JPY", "KMF", "KRW", "MGA", "PYG", "RWF", "UGX", "VND", "VUV", "XAF", "XOF", "XPF"]
        let threeDecimal = ["BHD", "JOD", "KWD", "OMR", "TND"]
        if zeroDecimal.contains(currency.uppercased()) { return 0 }
        if threeDecimal.contains(currency.uppercased()) { return 3 }
        return 2
    }

    var formattedAmount: String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currency
        f.maximumFractionDigits = amount.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
        return f.string(from: NSNumber(value: amount)) ?? "$\(amount)"
    }
}
