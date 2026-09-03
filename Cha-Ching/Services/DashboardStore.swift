import Foundation

@MainActor
final class DashboardStore: ObservableObject {
    typealias Loader = @MainActor (DashboardPeriod) async throws -> DashboardResponse

    @Published private(set) var dashboard: DashboardResponse?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var period: DashboardPeriod = .fourWeeks
    @Published var selectedCurrency: String?

    private let loader: Loader
    private var notificationObserver: NSObjectProtocol?
    private var refreshTask: Task<DashboardResponse, Error>?
    private var refreshGeneration = 0

    init(
        loader: @escaping Loader,
        notificationCenter: NotificationCenter = .default
    ) {
        self.loader = loader
        notificationObserver = notificationCenter.addObserver(
            forName: .chaChingPaymentsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    convenience init() {
        self.init { period in
            try await APIClient.shared.get("/v1/dashboard?period=\(period.rawValue)")
        }
    }

    func refresh() async {
        if let refreshTask {
            _ = await refreshTask.result
            return
        }
        isLoading = dashboard == nil
        errorMessage = nil
        let requestedPeriod = period
        refreshGeneration += 1
        let generation = refreshGeneration
        let task = Task { try await loader(requestedPeriod) }
        refreshTask = task
        defer {
            if generation == refreshGeneration {
                refreshTask = nil
                isLoading = false
            }
        }
        do {
            let response = try await task.value
            guard generation == refreshGeneration, requestedPeriod == period else { return }
            dashboard = response
            let available = response.report.totals.currencies.map(\.currency)
            if selectedCurrency == nil || !available.contains(selectedCurrency ?? "") {
                selectedCurrency = available.first ?? response.today.currencies.first?.currency
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = dashboard == nil
                ? "Dashboard couldn't load."
                : "Dashboard couldn't refresh."
        }
    }

    func selectPeriod(_ newPeriod: DashboardPeriod) async {
        guard period != newPeriod else { return }
        refreshTask?.cancel()
        refreshTask = nil
        refreshGeneration += 1
        period = newPeriod
        await refresh()
    }

    func reloadForReportingTimezoneChange() async {
        refreshTask?.cancel()
        refreshTask = nil
        refreshGeneration += 1
        await refresh()
    }

    var loadState: DashboardLoadState {
        if isLoading, dashboard == nil { return .loading }
        guard let dashboard else { return .unavailable }
        let isEmpty = dashboard.today.payments == 0
            && dashboard.report.totals.payments.current == 0
            && dashboard.report.products.isEmpty
            && dashboard.report.sources.isEmpty
        return .loaded(isEmpty: isEmpty)
    }

    var availableCurrencies: [String] {
        dashboard?.report.totals.currencies.map(\.currency) ?? []
    }

    func selectCurrency(_ currency: String) {
        guard availableCurrencies.contains(currency) else { return }
        selectedCurrency = currency
    }

    func dismissLoadError() {
        errorMessage = nil
    }

    func reset() {
        refreshTask?.cancel()
        refreshTask = nil
        refreshGeneration += 1
        dashboard = nil
        errorMessage = nil
        period = .fourWeeks
        selectedCurrency = nil
        isLoading = false
    }
}

enum DashboardLoadState: Equatable {
    case loading
    case loaded(isEmpty: Bool)
    case unavailable
}
