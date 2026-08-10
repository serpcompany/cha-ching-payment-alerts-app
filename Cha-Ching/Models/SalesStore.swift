import SwiftUI

@MainActor
final class SalesStore: ObservableObject {
    @Published var sales: [Sale] = []
    @Published var pingsEnabled: Bool = true
    @Published var soundName: String = "Cha-Ching"

    init() {
        sales = []
    }

    var todaysSales: [Sale] {
        let cal = Calendar.current
        return sales.filter { cal.isDateInToday($0.date) }
    }

    var todayTotal: Double { todaysSales.reduce(0) { $0 + $1.amount } }

    var last7DaysTotal: Double {
        let cutoff = Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date()
        return sales.filter { $0.date >= Calendar.current.startOfDay(for: cutoff) }
            .reduce(0) { $0 + $1.amount }
    }

    var yesterdayTotal: Double {
        let cal = Calendar.current
        return sales.filter { cal.isDateInYesterday($0.date) }.reduce(0) { $0 + $1.amount }
    }

    var dayOverDayChange: Double {
        guard yesterdayTotal > 0 else { return todayTotal > 0 ? 1 : 0 }
        return (todayTotal - yesterdayTotal) / yesterdayTotal
    }

    /// Daily totals for the last 7 days, oldest first.
    var weeklyTotals: [DayTotal] {
        let cal = Calendar.current
        return (0..<7).reversed().compactMap { offset in
            guard let day = cal.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            let total = sales.filter { cal.isDate($0.date, inSameDayAs: day) }
                .reduce(0) { $0 + $1.amount }
            return DayTotal(date: day, total: total)
        }
    }

    var topProduct: (name: String, total: Double)? {
        let grouped = Dictionary(grouping: sales, by: \.product)
            .mapValues { $0.reduce(0) { $0 + $1.amount } }
        guard let best = grouped.max(by: { $0.value < $1.value }) else { return nil }
        return (best.key, best.value)
    }

    func simulateSale() {
        let samples = [
            ("Pro Plan — Monthly", "ada@pixelforge.io", 19.0, Processor.stripe, true, "🇺🇸"),
            ("Icon Pack Vol. 3", "lu@studio.dk", 29.0, Processor.gumroad, false, "🇩🇰"),
            ("Lifetime License", "marc@brew.fr", 149.0, Processor.paypal, false, "🇫🇷")
        ]
        guard let pick = samples.randomElement() else { return }
        let sale = Sale(product: pick.0, customer: pick.1, amount: pick.2,
                        processor: pick.3, date: Date(), isSubscription: pick.4, country: pick.5)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            sales.insert(sale, at: 0)
        }
    }

    static func sampleSales() -> [Sale] {
        let now = Date()
        func ago(_ minutes: Int) -> Date { now.addingTimeInterval(TimeInterval(-minutes * 60)) }
        let raw: [(String, String, Double, Processor, Int, Bool, String)] = [
            ("Pro Plan — Monthly", "ada@pixelforge.io", 19, .stripe, 14, true, "🇺🇸"),
            ("Icon Pack Vol. 3", "lu@studio.dk", 29, .gumroad, 96, false, "🇩🇰"),
            ("Pro Plan — Yearly", "sam@northbound.co", 180, .stripe, 210, true, "🇨🇦"),
            ("Lifetime License", "marc@brew.fr", 149, .paypal, 320, false, "🇫🇷"),
            ("Pro Plan — Monthly", "kenji@makis.jp", 19, .stripe, 480, true, "🇯🇵"),
            ("SwiftUI Starter Kit", "nina@buildly.de", 49, .gumroad, 1500, false, "🇩🇪"),
            ("Pro Plan — Monthly", "omar@sandbox.ae", 19, .stripe, 1680, true, "🇦🇪"),
            ("Team Seat ×3", "ops@lumenapps.com", 57, .stripe, 2900, true, "🇬🇧"),
            ("Icon Pack Vol. 2", "tess@paperplane.nz", 24, .gumroad, 3400, false, "🇳🇿"),
            ("Lifetime License", "julia@corta.br", 149, .paypal, 4300, false, "🇧🇷"),
            ("Pro Plan — Yearly", "eli@ridgeline.io", 180, .stripe, 5600, true, "🇺🇸"),
            ("SwiftUI Starter Kit", "yuki@haru.jp", 49, .gumroad, 7200, false, "🇯🇵"),
            ("Pro Plan — Monthly", "raj@tinyloop.in", 19, .stripe, 8100, true, "🇮🇳"),
            ("Consulting Hour", "hello@finn.se", 120, .paypal, 8800, false, "🇸🇪")
        ]
        return raw.map {
            Sale(product: $0.0, customer: $0.1, amount: $0.2, processor: $0.3,
                 date: ago($0.4), isSubscription: $0.5, country: $0.6)
        }
    }
}

struct DayTotal: Identifiable {
    var id: Date { date }
    let date: Date
    let total: Double
}
