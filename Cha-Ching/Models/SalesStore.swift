import Foundation
import OSLog

private struct SalesResponse: Decodable {
    let sales: [SaleResponse]
}

private struct SaleResponse: Decodable {
    let id: String
    let provider: SaleSource
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
                    source: row.provider,
                    date: date,
                    isSubscription: row.isSubscription,
                    countryCode: row.countryCode
                )
            }
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            Self.logger.error("Sales refresh failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Couldn't load sales."
        }
    }

    var todaysSales: [Sale] {
        let calendar = Calendar.current
        return sales.filter { calendar.isDateInToday($0.date) }
    }

    var todayTotal: Double { todaysSales.reduce(0) { $0 + $1.amount } }

    var yesterdayTotal: Double {
        let calendar = Calendar.current
        return sales.filter { calendar.isDateInYesterday($0.date) }.reduce(0) { $0 + $1.amount }
    }

    var dayOverDayChange: Double {
        guard yesterdayTotal > 0 else { return todayTotal > 0 ? 1 : 0 }
        return (todayTotal - yesterdayTotal) / yesterdayTotal
    }

}
