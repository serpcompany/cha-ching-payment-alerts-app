import Foundation
import OSLog

private struct SalesResponse: Decodable {
    let sales: [SaleResponse]
}

private struct SaleResponseEnvelope: Decodable {
    let sale: SaleResponse
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
    let notificationFields: [SaleDetail]?
}

struct SalesClient: Sendable {
    let load: @MainActor @Sendable () async throws -> [Sale]
    let loadByID: @MainActor @Sendable (String) async throws -> Sale?

    init(
        load: @escaping @MainActor @Sendable () async throws -> [Sale],
        loadByID: @escaping @MainActor @Sendable (String) async throws -> Sale? = { _ in nil }
    ) {
        self.load = load
        self.loadByID = loadByID
    }

    static let live = SalesClient(
        load: {
            guard APIClient.shared.hasAuthToken else { return [] }
            let response: SalesResponse = try await APIClient.shared.get("/v1/sales")
            return payments(from: response)
        },
        loadByID: { id in
            guard APIClient.shared.hasAuthToken else { return nil }
            do {
                let response: SaleResponseEnvelope = try await APIClient.shared.get(
                    pathComponents: ["v1", "sales", id]
                )
                return payment(from: response.sale)
            } catch APIError.notFound {
                return nil
            }
        }
    )

    static func decode(_ data: Data) throws -> [Sale] {
        payments(from: try JSONDecoder().decode(SalesResponse.self, from: data))
    }

    private static func payments(from response: SalesResponse) -> [Sale] {
        return response.sales.compactMap(payment(from:))
    }

    private static func payment(from row: SaleResponse) -> Sale? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: row.occurredAt) else { return nil }
        return Sale(
            id: row.id,
            product: row.productLabel,
            amountMinor: row.amountMinor,
            currency: row.currency,
            source: row.provider,
            date: date,
            isSubscription: row.isSubscription,
            countryCode: row.countryCode,
            details: row.notificationFields ?? []
        )
    }
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
    private var needsTrailingRefresh = false

    convenience init() {
        self.init(client: .live)
    }

    init(client: SalesClient, notificationCenter: NotificationCenter = .default) {
        self.client = client
        notificationObserver = notificationCenter.addObserver(
            forName: .chaChingPaymentsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refreshAfterPaymentsChanged() }
        }
    }

    func refresh() async {
        await refresh(markDirtyWhenCoalesced: false)
    }

    private func refreshAfterPaymentsChanged() async {
        await refresh(markDirtyWhenCoalesced: true)
    }

    private func refresh(markDirtyWhenCoalesced: Bool) async {
        let operation: RefreshOperation
        if let existing = refreshOperation {
            if markDirtyWhenCoalesced { needsTrailingRefresh = true }
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
        let shouldRefreshAgain = needsTrailingRefresh
        needsTrailingRefresh = false
        if shouldRefreshAgain { await refresh() }
    }

    func dismissLoadError() {
        errorMessage = nil
    }

    func reset() {
        refreshOperation?.task.cancel()
        refreshOperation = nil
        needsTrailingRefresh = false
        sales = []
        isLoading = false
        errorMessage = nil
    }

    func sale(id: String) -> Sale? {
        sales.first { $0.id == id }
    }

    func resolveNotificationSale(id: String) async -> NotificationSaleResolution {
        if let loaded = sale(id: id) { return .found(loaded) }
        do {
            guard let exact = try await client.loadByID(id) else { return .missing }
            return .found(exact)
        } catch {
            return .failed
        }
    }
}

enum NotificationSaleResolution: Equatable {
    case found(Sale)
    case missing
    case failed
}
