import Foundation

enum DashboardPeriod: String, CaseIterable, Codable, Identifiable {
    case oneWeek = "1w"
    case fourWeeks = "4w"
    case oneYear = "1y"
    case monthToDate = "mtd"
    case quarterToDate = "qtd"
    case yearToDate = "ytd"
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneWeek: "1 week"
        case .fourWeeks: "4 weeks"
        case .oneYear: "1 year"
        case .monthToDate: "Month to date"
        case .quarterToDate: "Quarter to date"
        case .yearToDate: "Year to date"
        case .all: "All time"
        }
    }
}

struct DashboardResponse: Decodable {
    let reportingTimezone: String
    let generatedAt: Date
    let period: DashboardPeriod
    let today: DashboardToday
    let report: DashboardReport
}

struct DashboardToday: Decodable {
    let start: Date
    let end: Date
    let payments: Int
    let currencies: [DashboardMoneyTotal]
}

struct DashboardMoneyTotal: Decodable, Identifiable {
    let currency: String
    let grossAmountMinor: Int
    let averageAmountMinor: Int
    var id: String { currency }
}

struct DashboardReport: Decodable {
    let current: DashboardWindow
    let previous: DashboardWindow?
    let totals: DashboardTotals
    let currentSeries: [DashboardBucket]
    let previousSeries: [DashboardBucket]
    let products: [DashboardBreakdown]
    let sources: [DashboardBreakdown]
}

struct DashboardWindow: Decodable {
    let start: Date
    let end: Date
}

struct DashboardTotals: Decodable {
    let payments: DashboardCountComparison
    let currencies: [DashboardCurrencyComparison]
}

struct DashboardCountComparison: Decodable {
    let current: Int
    let previous: Int
    let comparison: DashboardComparison
}

struct DashboardCurrencyComparison: Decodable, Identifiable {
    let currency: String
    let currentAmountMinor: Int
    let previousAmountMinor: Int
    let comparison: DashboardComparison
    var id: String { currency }
}

struct DashboardComparison: Decodable, Equatable {
    enum State: String, Decodable {
        case percent
        case new
        case none
    }

    let state: State
    let percent: Double?

    var text: String {
        switch state {
        case .new: "New"
        case .none: "—"
        case .percent:
            {
                let value = Int((percent ?? 0).rounded())
                return value > 0 ? "+\(value)%" : "\(value)%"
            }()
        }
    }
}

struct DashboardBucket: Decodable, Identifiable {
    let start: Date
    let end: Date
    let payments: Int
    let amounts: [DashboardMoneyTotal]
    var id: Date { start }

    func amount(for currency: String) -> Int {
        amounts.first { $0.currency == currency }?.grossAmountMinor ?? 0
    }
}

struct DashboardBreakdown: Decodable, Identifiable {
    let label: String
    let payments: Int
    let amounts: [DashboardMoneyTotal]
    var id: String { label }

    func amount(for currency: String) -> Int {
        amounts.first { $0.currency == currency }?.grossAmountMinor ?? 0
    }
}

enum DashboardFormatting {
    static func money(minor: Int, currency: String) -> String {
        let exponent = currencyExponent(currency)
        let amount = Double(minor) / pow(10, Double(exponent))
        return amount.formatted(.currency(code: currency).precision(.fractionLength(exponent)))
    }

    private static func currencyExponent(_ currency: String) -> Int {
        let zeroDecimal = ["BIF", "CLP", "DJF", "GNF", "JPY", "KMF", "KRW", "MGA", "PYG", "RWF", "UGX", "VND", "VUV", "XAF", "XOF", "XPF"]
        let threeDecimal = ["BHD", "JOD", "KWD", "OMR", "TND"]
        if zeroDecimal.contains(currency.uppercased()) { return 0 }
        if threeDecimal.contains(currency.uppercased()) { return 3 }
        return 2
    }
}
