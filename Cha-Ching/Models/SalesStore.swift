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

struct SalesClient: Sendable {
    let load: @MainActor @Sendable () async throws -> [Sale]

    static let live = SalesClient(load: {
        guard APIClient.shared.hasAuthToken else { return [] }
        let response: SalesResponse = try await APIClient.shared.get("/v1/sales")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return response.sales.compactMap { row in
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
    })
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

    private let client: SalesClient
    private var notificationObserver: NSObjectProtocol?

    convenience init() {
        self.init(client: .live)
    }

    init(client: SalesClient) {
        self.client = client
        notificationObserver = NotificationCenter.default.addObserver(
            forName: .chaChingSaleReceived,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            sales = try await client.load()
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            Self.logger.error("Sales refresh failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Payments couldn't refresh."
        }
    }

    func dismissLoadError() {
        errorMessage = nil
    }
}
