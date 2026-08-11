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

    private struct RefreshOperation {
        let id: UUID
        let task: Task<[Sale], Error>
    }

    private let client: SalesClient
    private var notificationObserver: NSObjectProtocol?
    private var refreshOperation: RefreshOperation?

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
        let operation: RefreshOperation
        if let existing = refreshOperation {
            operation = existing
        } else {
            isLoading = true
            errorMessage = nil
            let created = RefreshOperation(
                id: UUID(),
                task: Task { try await client.load() }
            )
            refreshOperation = created
            operation = created
        }

        do {
            let refreshedSales = try await operation.task.value
            guard refreshOperation?.id == operation.id else { return }
            sales = refreshedSales
            errorMessage = nil
        } catch is CancellationError {
            // View lifecycle cancellation is not a failed server refresh.
        } catch let error as URLError where error.code == .cancelled {
            // URLSession can surface cancellation as URLError instead.
        } catch {
            guard refreshOperation?.id == operation.id else { return }
            Self.logger.error("Sales refresh failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Payments couldn't refresh."
        }

        guard refreshOperation?.id == operation.id else { return }
        refreshOperation = nil
        isLoading = false
    }

    func dismissLoadError() {
        errorMessage = nil
    }
}
