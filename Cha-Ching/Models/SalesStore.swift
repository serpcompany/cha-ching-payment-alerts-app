import Foundation
import OSLog

private struct SalesResponse: Decodable {
    let sales: [SaleResponse]
}

private struct SaleResponse: Decodable {
    let id: String
    let provider: Processor
    let amountMinor: Int
    let currency: String
    let productLabel: String
    let countryCode: String?
    let isSubscription: Bool
    let occurredAt: String
}

@MainActor
final class SalesStore: ObservableObject {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.serpcompany.chaching",
        category: "sales"
    )

    @Published private(set) var sales: [Sale] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private var notificationObserver: NSObjectProtocol?

    init() {
        notificationObserver = NotificationCenter.default.addObserver(
            forName: .chaChingSaleReceived,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    func refresh() async {
        guard APIClient.shared.hasAuthToken else {
            sales = []
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let response: SalesResponse = try await APIClient.shared.get("/v1/sales")
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            sales = response.sales.compactMap { row in
                guard let date = formatter.date(from: row.occurredAt) else { return nil }
                return Sale(
                    id: row.id,
                    product: row.productLabel,
                    amountMinor: row.amountMinor,
                    currency: row.currency,
                    processor: row.provider,
                    date: date,
                    isSubscription: row.isSubscription,
                    countryCode: row.countryCode
                )
            }
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            Self.logger.error("Verified sales refresh failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Couldn't load verified sales."
        }
    }

    var todaysSales: [Sale] {
        let calendar = Calendar.current
        return sales.filter { calendar.isDateInToday($0.date) }
    }

    var todayTotal: Double { todaysSales.reduce(0) { $0 + $1.amount } }

    var last7DaysTotal: Double {
        let cutoff = Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date()
        return sales.filter { $0.date >= Calendar.current.startOfDay(for: cutoff) }
            .reduce(0) { $0 + $1.amount }
    }

    var yesterdayTotal: Double {
        let calendar = Calendar.current
        return sales.filter { calendar.isDateInYesterday($0.date) }.reduce(0) { $0 + $1.amount }
    }

    var dayOverDayChange: Double {
        guard yesterdayTotal > 0 else { return todayTotal > 0 ? 1 : 0 }
        return (todayTotal - yesterdayTotal) / yesterdayTotal
    }

    var weeklyTotals: [DayTotal] {
        let calendar = Calendar.current
        return (0..<7).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            let total = sales.filter { calendar.isDate($0.date, inSameDayAs: day) }
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
}

struct DayTotal: Identifiable {
    var id: Date { date }
    let date: Date
    let total: Double
}
