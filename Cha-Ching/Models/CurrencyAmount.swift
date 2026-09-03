import Foundation

enum CurrencyAmount {
    private static let zeroDecimal = Set([
        "BIF", "CLP", "DJF", "GNF", "JPY", "KMF", "KRW", "MGA", "PYG",
        "RWF", "UGX", "VND", "VUV", "XAF", "XOF", "XPF"
    ])
    private static let threeDecimal = Set(["BHD", "JOD", "KWD", "OMR", "TND"])

    static func exponent(for currency: String) -> Int {
        let code = currency.uppercased()
        if zeroDecimal.contains(code) { return 0 }
        if threeDecimal.contains(code) { return 3 }
        return 2
    }

    static func value(minor: Int, currency: String) -> Double {
        Double(minor) / pow(10, Double(exponent(for: currency)))
    }

    static func formatted(minor: Int, currency: String, trimWholeUnits: Bool = false) -> String {
        let code = currency.uppercased()
        let exponent = exponent(for: code)
        let value = value(minor: minor, currency: code)
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.maximumFractionDigits = exponent
        formatter.minimumFractionDigits = trimWholeUnits && value.rounded() == value ? 0 : exponent
        return formatter.string(from: NSNumber(value: value)) ?? "\(minor) \(code)"
    }
}
