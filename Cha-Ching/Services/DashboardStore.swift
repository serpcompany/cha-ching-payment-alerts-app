import Foundation

@MainActor
final class DashboardStore: ObservableObject {
    typealias Loader = @MainActor (DashboardPeriod, Int) async throws -> DashboardResponse

    @Published private(set) var dashboard: DashboardResponse?
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshing = false
    @Published var errorMessage: String?
    @Published var period: DashboardPeriod = .fourWeeks
    @Published private(set) var dayOffset = 0
    @Published var selectedCurrency: String?

    private let loader: Loader
    private var notificationObserver: NSObjectProtocol?
    private var refreshTask: Task<DashboardResponse, Error>?
    private var refreshGeneration = 0
    private var needsTrailingRefresh = false

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
            Task { @MainActor in await self?.refreshAfterPaymentsChanged() }
        }
    }

    convenience init() {
        self.init { period, dayOffset in
            try await APIClient.shared.get(
                "/v1/dashboard",
                queryItems: [
                    URLQueryItem(name: "period", value: period.rawValue),
                    URLQueryItem(name: "dayOffset", value: String(dayOffset))
                ]
            )
        }
    }

    func refresh() async {
        await refresh(markDirtyWhenCoalesced: false)
    }

    private func refreshAfterPaymentsChanged() async {
        await refresh(markDirtyWhenCoalesced: true)
    }

    private func refresh(markDirtyWhenCoalesced: Bool) async {
        if let refreshTask {
            if markDirtyWhenCoalesced { needsTrailingRefresh = true }
            _ = await refreshTask.result
            return
        }
        isLoading = dashboard == nil
        isRefreshing = true
        errorMessage = nil
        let requestedPeriod = period
        let requestedDayOffset = dayOffset
        refreshGeneration += 1
        let generation = refreshGeneration
        let task = Task { try await loader(requestedPeriod, requestedDayOffset) }
        refreshTask = task
        do {
            let response = try await task.value
            guard response.dayOffset == requestedDayOffset else { throw APIError.invalidResponse }
            if generation == refreshGeneration,
               requestedPeriod == period,
               requestedDayOffset == dayOffset {
                dashboard = response
                let available = availableCurrencies(in: response)
                if selectedCurrency == nil || !available.contains(selectedCurrency ?? "") {
                    selectedCurrency = available.first ?? response.dailySummary.currencies.first?.currency
                }
            }
        } catch is CancellationError {
            // A period/timezone/reset generation owns the replacement state.
        } catch {
            if generation == refreshGeneration {
                errorMessage = dashboard == nil
                    ? "Dashboard couldn't load."
                    : "Dashboard couldn't refresh."
            }
        }
        guard generation == refreshGeneration else { return }
        refreshTask = nil
        isLoading = false
        isRefreshing = false
        let shouldRefreshAgain = needsTrailingRefresh
        needsTrailingRefresh = false
        if shouldRefreshAgain { await refresh() }
    }

    func selectPeriod(_ newPeriod: DashboardPeriod) async {
        guard period != newPeriod else { return }
        refreshTask?.cancel()
        refreshTask = nil
        refreshGeneration += 1
        needsTrailingRefresh = false
        period = newPeriod
        await refresh()
    }

    func selectPreviousDay() async {
        guard !isRefreshing else { return }
        await selectDayOffset(dayOffset + 1)
    }

    func selectNextDay() async {
        guard !isRefreshing, dayOffset > 0 else { return }
        await selectDayOffset(dayOffset - 1)
    }

    private func selectDayOffset(_ newDayOffset: Int) async {
        let previousDayOffset = dayOffset
        refreshTask?.cancel()
        refreshTask = nil
        refreshGeneration += 1
        needsTrailingRefresh = false
        dayOffset = newDayOffset
        await refresh()
        if errorMessage != nil,
           dayOffset == newDayOffset,
           dashboard?.dayOffset != newDayOffset {
            dayOffset = previousDayOffset
        }
    }

    func reloadForReportingTimezoneChange() async {
        refreshTask?.cancel()
        refreshTask = nil
        refreshGeneration += 1
        needsTrailingRefresh = false
        await refresh()
    }

    var loadState: DashboardLoadState {
        if isLoading, dashboard == nil { return .loading }
        guard let dashboard else { return .unavailable }
        let isEmpty = dashboard.dailySummary.payments == 0
            && dashboard.report.totals.payments.current == 0
            && dashboard.report.products.isEmpty
            && dashboard.report.sources.isEmpty
        return .loaded(isEmpty: isEmpty)
    }

    var availableCurrencies: [String] {
        guard let dashboard else { return [] }
        return availableCurrencies(in: dashboard)
    }

    private func availableCurrencies(in dashboard: DashboardResponse) -> [String] {
        let reportCurrencies = dashboard.report.totals.currencies.map(\.currency)
        return reportCurrencies + dashboard.dailySummary.currencies.map(\.currency).filter {
            !reportCurrencies.contains($0)
        }
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
        needsTrailingRefresh = false
        dashboard = nil
        errorMessage = nil
        period = .fourWeeks
        dayOffset = 0
        selectedCurrency = nil
        isLoading = false
        isRefreshing = false
    }
}

enum DashboardLoadState: Equatable {
    case loading
    case loaded(isEmpty: Bool)
    case unavailable
}
