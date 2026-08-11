import SwiftUI

enum Provider: String, CaseIterable, Identifiable, Codable {
    case stripe, paypal

    var id: String { rawValue }

    static let mvpProviders: [Provider] = [.stripe, .paypal]

    var title: String {
        switch self {
        case .stripe: return "Stripe"
        case .paypal: return "PayPal"
        }
    }

    var symbol: String {
        switch self {
        case .stripe: return "creditcard.fill"
        case .paypal: return "p.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .stripe: return Theme.adaptive(light: (0.39, 0.36, 0.94), dark: (0.55, 0.53, 1.0))
        case .paypal: return Theme.adaptive(light: (0.0, 0.44, 0.75), dark: (0.35, 0.68, 1.0))
        }
    }

    /// How a user grants Cha-Ching access at the provider.
    var setupHint: String {
        switch self {
        case .stripe: return "Install Cha-Ching from Stripe's permission screen. It can read successful payment events, but it cannot create or change payments."
        case .paypal: return "Sign in to PayPal and choose the account you want Cha-Ching to link."
        }
    }
}

enum SaleSource: String, Codable, Hashable {
    case stripe, paypal, custom

    var title: String {
        switch self {
        case .stripe: "Stripe"
        case .paypal: "PayPal"
        case .custom: "Custom payment source"
        }
    }

    var symbol: String {
        switch self {
        case .stripe: "creditcard.fill"
        case .paypal: "p.circle.fill"
        case .custom: "point.3.connected.trianglepath.dotted"
        }
    }

    var color: Color {
        switch self {
        case .stripe: Theme.adaptive(light: (0.39, 0.36, 0.94), dark: (0.55, 0.53, 1.0))
        case .paypal: Theme.adaptive(light: (0.0, 0.44, 0.75), dark: (0.35, 0.68, 1.0))
        case .custom: Theme.accent
        }
    }

    var attribution: String {
        switch self {
        case .stripe: "Verified by Stripe"
        case .paypal: "Verified by PayPal"
        case .custom: "Reported by your custom source"
        }
    }
}

struct SaleDetail: Codable, Hashable {
    let label: String
    let value: String
}

struct Sale: Identifiable, Hashable {
    let id: String
    let product: String
    let amountMinor: Int
    let currency: String
    let source: SaleSource
    let date: Date
    let isSubscription: Bool
    let countryCode: String?
    let details: [SaleDetail]

    init(
        id: String,
        product: String,
        amountMinor: Int,
        currency: String,
        source: SaleSource,
        date: Date,
        isSubscription: Bool,
        countryCode: String?,
        details: [SaleDetail] = []
    ) {
        self.id = id
        self.product = product
        self.amountMinor = amountMinor
        self.currency = currency
        self.source = source
        self.date = date
        self.isSubscription = isSubscription
        self.countryCode = countryCode
        self.details = details
    }

    var amount: Double {
        Double(amountMinor) / pow(10, Double(currencyExponent))
    }

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
