import Foundation
import Testing
@testable import Cha_Ching

struct DashboardTests {
    @Test func decodesTheDashboardContractAndEveryPeriod() throws {
        for period in DashboardPeriod.allCases {
            let data = Data(responseJSON(period: period.rawValue).utf8)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let response = try decoder.decode(DashboardResponse.self, from: data)

            #expect(response.period == period)
            #expect(response.dayOffset == 0)
            #expect(response.reportingTimezone == "Asia/Tokyo")
            #expect(response.dailySummary.payments == 2)
            #expect(response.dailySummary.currencies.first?.grossAmountMinor == 2700)
            #expect(response.dailySummary.currencies.first?.payments == 2)
            #expect(response.report.currentSeries.first?.amounts.amount(for: "USD") == 2700)
            #expect(response.report.products.first?.label == "Widget")
        }
    }

    @Test func comparisonStatesHaveTruthfulLabels() {
        #expect(DashboardComparison(state: .new, percent: nil).text == "New")
        #expect(DashboardComparison(state: .none, percent: nil).text == "—")
        #expect(DashboardComparison(state: .percent, percent: -100).text == "-100%")
        #expect(DashboardComparison(state: .percent, percent: 8).text == "+8%")
    }

    @Test func moneyFormattingKeepsCurrenciesSeparateAndRespectsExponent() {
        let usd = DashboardFormatting.money(minor: 21350, currency: "USD")
        let yen = DashboardFormatting.money(minor: 21350, currency: "JPY")

        #expect(usd.contains("213.50"))
        #expect(yen.contains("21,350"))
        #expect(usd != yen)
        #expect(CurrencyAmount.exponent(for: "BHD") == 3)
        #expect(CurrencyAmount.exponent(for: "jpy") == 0)
    }

    @MainActor
    @Test func refreshFailurePreservesTheLoadedDashboard() async throws {
        let response = try decodedResponse()
        let failure = DashboardFailureSwitch()
        let store = DashboardStore { _, _ in
            if failure.shouldFail { throw URLError(.notConnectedToInternet) }
            return response
        }
        await store.refresh()
        let loadedAt = store.dashboard?.generatedAt
        failure.shouldFail = true
        await store.refresh()

        #expect(store.dashboard?.generatedAt == loadedAt)
        #expect(store.errorMessage == "Dashboard couldn't refresh.")
        store.dismissLoadError()
        #expect(store.errorMessage == nil)
    }

    @MainActor
    @Test func periodAndCurrencySelectionsRefreshAndStayValid() async throws {
        let response = try decodedResponse()
        var requestedPeriods: [DashboardPeriod] = []
        let store = DashboardStore { period, _ in
            requestedPeriods.append(period)
            return response
        }

        await store.refresh()
        await store.selectPeriod(.oneWeek)
        store.selectCurrency("USD")
        store.selectCurrency("EUR")

        #expect(requestedPeriods == [.fourWeeks, .oneWeek])
        #expect(store.period == .oneWeek)
        #expect(store.selectedCurrency == "USD")
    }

    @MainActor
    @Test func carouselScrollPositionSynchronizesWithDayOffset() async throws {
        var requests: [(period: DashboardPeriod, dayOffset: Int)] = []
        let responses = try (0...2).map { try decodedResponse(dayOffset: $0) }
        let store = DashboardStore { period, dayOffset in
            requests.append((period, dayOffset))
            return responses[dayOffset]
        }

        await store.refresh()
        #expect(store.carouselDayOffsets == [1, 0])
        await store.selectDayOffset(1)
        #expect(store.carouselDayOffsets == [2, 1, 0])
        await store.selectDayOffset(2)
        await store.selectDayOffset(1)
        await store.selectDayOffset(0)

        #expect(requests.map(\.dayOffset) == [0, 1, 2, 1, 0])
        #expect(store.dayOffset == 0)
        #expect(store.dashboard?.dayOffset == 0)
    }

    @MainActor
    @Test func carouselRejectsFutureDayPositionsWithoutLoading() async throws {
        let today = try decodedResponse()
        var requests: [Int] = []
        let store = DashboardStore { _, dayOffset in
            requests.append(dayOffset)
            return today
        }

        await store.refresh()
        await store.selectDayOffset(-1)
        await store.selectDayOffset(0)

        #expect(requests == [0])
        #expect(store.dayOffset == 0)
        #expect(store.carouselDayOffsets == [1, 0])
    }

    @MainActor
    @Test func carouselPrefetchCachesRealNeighborSummary() async throws {
        let today = try decodedResponse()
        let priorDay = try decodedResponse(dayOffset: 1)
        let store = DashboardStore(
            loader: { _, _ in today },
            prefetchLoader: { _, dayOffset in
                #expect(dayOffset == 1)
                return priorDay
            }
        )

        await store.refresh()
        while store.dailySummary(for: 1) == nil { await Task.yield() }

        #expect(store.dailySummary(for: 0)?.payments == today.dailySummary.payments)
        #expect(store.dailySummary(for: 1)?.start == priorDay.dailySummary.start)
    }

    @MainActor
    @Test func failedDailySummaryNavigationKeepsTheDisplayedDaySelected() async throws {
        let today = try decodedResponse()
        let store = DashboardStore { _, dayOffset in
            if dayOffset > 0 { throw URLError(.notConnectedToInternet) }
            return today
        }

        await store.refresh()
        await store.selectDayOffset(1)

        #expect(store.dayOffset == 0)
        #expect(store.dashboard?.dayOffset == 0)
        #expect(store.errorMessage == "Dashboard couldn't refresh.")
    }

    @MainActor
    @Test func staleCarouselRequestCannotReplaceNewerSelectedDay() async throws {
        let today = try decodedResponse()
        let oneDayAgo = try decodedResponse(dayOffset: 1)
        let twoDaysAgo = try decodedResponse(dayOffset: 2)
        let loader = DayOffsetControlledLoader()
        let store = DashboardStore { _, dayOffset in
            if dayOffset == 0 { return today }
            return try await loader.load(dayOffset)
        }

        await store.refresh()
        let firstSelection = Task { await store.selectDayOffset(1) }
        while !loader.hasPending(offset: 1) { await Task.yield() }
        let secondSelection = Task { await store.selectDayOffset(2) }
        while !loader.hasPending(offset: 2) { await Task.yield() }

        loader.finish(offset: 2, with: twoDaysAgo)
        await secondSelection.value
        loader.finish(offset: 1, with: oneDayAgo)
        await firstSelection.value

        #expect(store.dayOffset == 2)
        #expect(store.dashboard?.dayOffset == 2)
        #expect(store.dailySummary(for: 1) == nil)
        #expect(store.dailySummary(for: 2)?.payments == twoDaysAgo.dailySummary.payments)
    }

    @MainActor
    @Test func timezoneChangeInvalidatesAnOlderInFlightDashboard() async throws {
        let old = try decodedResponse(timezone: "America/New_York")
        let new = try decodedResponse(timezone: "Asia/Tokyo")
        let loader = ControlledDashboardLoader(first: old, second: new)
        let store = DashboardStore { period, dayOffset in try await loader.load(period, dayOffset) }

        let oldRefresh = Task { await store.refresh() }
        while loader.callCount == 0 { await Task.yield() }
        await store.reloadForReportingTimezoneChange()
        loader.finishFirst()
        await oldRefresh.value

        #expect(loader.callCount == 2)
        #expect(store.dashboard?.reportingTimezone == "Asia/Tokyo")
    }

    @MainActor
    @Test func foregroundSaleNotificationsDuringFetchCoalesceIntoOneTrailingRefresh() async throws {
        let response = try decodedResponse()
        let center = NotificationCenter()
        let loader = ControlledDashboardLoader(first: response, second: response)
        let store = DashboardStore(
            loader: { period, dayOffset in try await loader.load(period, dayOffset) },
            notificationCenter: center
        )

        PaymentHistoryEvents.changed(notificationCenter: center)
        PaymentHistoryEvents.changed(notificationCenter: center)
        while loader.callCount == 0 { await Task.yield() }
        #expect(loader.callCount == 1)
        loader.finishFirst()
        while loader.callCount < 2 { await Task.yield() }

        #expect(store.dashboard?.dailySummary.payments == 2)
        #expect(loader.callCount == 2)
    }

    @MainActor
    @Test func paymentHistoryChangesRefreshDashboardAfterClear() async throws {
        let populated = try decodedResponse()
        let empty = try decodedResponse(isEmpty: true)
        let center = NotificationCenter()
        let loader = ControlledDashboardLoader(first: populated, second: empty)
        let store = DashboardStore(
            loader: { period, dayOffset in try await loader.load(period, dayOffset) },
            notificationCenter: center
        )
        let initial = Task { await store.refresh() }
        while loader.callCount == 0 { await Task.yield() }
        PaymentHistoryEvents.changed(notificationCenter: center)
        loader.finishFirst()
        await initial.value
        while loader.callCount < 2 || store.dashboard?.dailySummary.payments != 0 { await Task.yield() }

        #expect(store.dashboard?.dailySummary.payments == 0)
    }

    @MainActor
    @Test func loadingEmptyAndInitialErrorStatesAreExplicit() async throws {
        let response = try decodedResponse(isEmpty: true)
        let loader = ControlledDashboardLoader(first: response, second: response)
        let loadingStore = DashboardStore { period, dayOffset in try await loader.load(period, dayOffset) }
        #expect(loadingStore.loadState == .unavailable)
        let refresh = Task { await loadingStore.refresh() }
        while loader.callCount == 0 { await Task.yield() }
        #expect(loadingStore.loadState == .loading)
        loader.finishFirst()
        await refresh.value
        #expect(loadingStore.loadState == .loaded(isEmpty: true))

        let failingStore = DashboardStore { _, _ in throw URLError(.notConnectedToInternet) }
        await failingStore.refresh()
        #expect(failingStore.loadState == .unavailable)
        #expect(failingStore.errorMessage == "Dashboard couldn't load.")
    }

    @Test func chartAccessibilityFormatsGrossVolumeInTheSelectedCurrency() {
        let label = DashboardChartAccessibility.grossVolume(
            current: [10_000, 11_350],
            previous: [8_000],
            currency: "USD"
        )

        #expect(label.contains("213.50"))
        #expect(label.contains("80.00"))
        #expect(!label.contains("21350"))
        #expect(DashboardChartAccessibility.payments(current: [3, 4], previous: [2])
            == "Payments chart. Current total 7; previous total 2.")
        let allGross = DashboardChartAccessibility.grossVolume(
            current: [21_350], previous: nil, currency: "USD"
        )
        let allPayments = DashboardChartAccessibility.payments(current: [3, 4], previous: nil)
        #expect(allGross.contains("213.50"))
        #expect(!allGross.localizedCaseInsensitiveContains("previous"))
        #expect(allPayments == "Payments chart. Current total 7.")
        #expect(!allPayments.localizedCaseInsensitiveContains("previous"))
    }

    private func decodedResponse(
        timezone: String = "Asia/Tokyo",
        isEmpty: Bool = false,
        dayOffset: Int = 0
    ) throws -> DashboardResponse {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            DashboardResponse.self,
            from: Data(responseJSON(
                period: "4w",
                timezone: timezone,
                isEmpty: isEmpty,
                dayOffset: dayOffset
            ).utf8)
        )
    }

    private func responseJSON(
        period: String,
        timezone: String = "Asia/Tokyo",
        isEmpty: Bool = false,
        dayOffset: Int = 0
    ) -> String {
        let currentPayments = isEmpty ? 0 : 2
        let currencies = isEmpty
            ? "[]"
            : "[{\"currency\":\"USD\",\"payments\":2,\"grossAmountMinor\":2700,\"averageAmountMinor\":1350}]"
        let comparedCurrencies = isEmpty
            ? "[]"
            : "[{\"currency\":\"USD\",\"currentAmountMinor\":2700,\"previousAmountMinor\":1000,\"comparison\":{\"state\":\"percent\",\"percent\":170}}]"
        let series = isEmpty
            ? "[]"
            : "[{\"start\":\"2026-09-02T15:00:00Z\",\"end\":\"2026-09-03T12:00:00Z\",\"payments\":2,\"amounts\":[{\"currency\":\"USD\",\"payments\":2,\"grossAmountMinor\":2700,\"averageAmountMinor\":1350}]}]"
        let products = isEmpty
            ? "[]"
            : "[{\"label\":\"Widget\",\"amounts\":[{\"currency\":\"USD\",\"payments\":2,\"grossAmountMinor\":2700,\"averageAmountMinor\":1350}]}]"
        let sources = isEmpty
            ? "[]"
            : "[{\"label\":\"Stripe\",\"amounts\":[{\"currency\":\"USD\",\"payments\":2,\"grossAmountMinor\":2700,\"averageAmountMinor\":1350}]}]"
        return """
        {
          "reportingTimezone": "\(timezone)",
          "generatedAt": "2026-09-03T12:00:00Z",
          "period": "\(period)",
          "dayOffset": \(dayOffset),
          "today": {
            "start": "2026-09-02T15:00:00Z",
            "end": "2026-09-03T12:00:00Z",
            "payments": \(currentPayments),
            "currencies": \(currencies)
          },
          "report": {
            "current": {"start":"2026-08-06T15:00:00Z","end":"2026-09-03T12:00:00Z"},
            "previous": {"start":"2026-07-08T18:00:00Z","end":"2026-08-06T15:00:00Z"},
            "totals": {
              "payments": {"current":\(currentPayments),"previous":1,"comparison":{"state":"percent","percent":100}},
              "currencies": \(comparedCurrencies)
            },
            "currentSeries": \(series),
            "previousSeries": [],
            "products": \(products),
            "sources": \(sources)
          }
        }
        """
    }

}

@MainActor
private final class ControlledDashboardLoader {
    private let first: DashboardResponse
    private let second: DashboardResponse
    private var firstContinuation: CheckedContinuation<DashboardResponse, Error>?
    private(set) var callCount = 0

    init(first: DashboardResponse, second: DashboardResponse) {
        self.first = first
        self.second = second
    }

    func load(_ period: DashboardPeriod, _ dayOffset: Int) async throws -> DashboardResponse {
        callCount += 1
        if callCount == 1 {
            return try await withCheckedThrowingContinuation { continuation in
                firstContinuation = continuation
            }
        }
        return second
    }

    func finishFirst() {
        firstContinuation?.resume(returning: first)
        firstContinuation = nil
    }
}

@MainActor
private final class DashboardFailureSwitch {
    var shouldFail = false
}

@MainActor
private final class DayOffsetControlledLoader {
    private var continuations: [Int: CheckedContinuation<DashboardResponse, Error>] = [:]

    func load(_ dayOffset: Int) async throws -> DashboardResponse {
        try await withCheckedThrowingContinuation { continuation in
            continuations[dayOffset] = continuation
        }
    }

    func hasPending(offset: Int) -> Bool {
        continuations[offset] != nil
    }

    func finish(offset: Int, with response: DashboardResponse) {
        continuations.removeValue(forKey: offset)?.resume(returning: response)
    }
}
