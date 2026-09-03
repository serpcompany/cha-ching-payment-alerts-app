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
            #expect(response.reportingTimezone == "Asia/Tokyo")
            #expect(response.today.payments == 2)
            #expect(response.today.currencies.first?.grossAmountMinor == 2700)
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
    }

    @MainActor
    @Test func refreshFailurePreservesTheLoadedDashboard() async throws {
        let response = try decodedResponse()
        let failure = DashboardFailureSwitch()
        let store = DashboardStore { _ in
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
        let store = DashboardStore { period in
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
    @Test func timezoneChangeInvalidatesAnOlderInFlightDashboard() async throws {
        let old = try decodedResponse(timezone: "America/New_York")
        let new = try decodedResponse(timezone: "Asia/Tokyo")
        let loader = ControlledDashboardLoader(first: old, second: new)
        let store = DashboardStore { period in try await loader.load(period) }

        let oldRefresh = Task { await store.refresh() }
        while loader.callCount == 0 { await Task.yield() }
        await store.reloadForReportingTimezoneChange()
        loader.finishFirst()
        await oldRefresh.value

        #expect(loader.callCount == 2)
        #expect(store.dashboard?.reportingTimezone == "Asia/Tokyo")
    }

    @MainActor
    @Test func loadingEmptyAndInitialErrorStatesAreExplicit() async throws {
        let response = try decodedResponse(isEmpty: true)
        let loader = ControlledDashboardLoader(first: response, second: response)
        let loadingStore = DashboardStore { period in try await loader.load(period) }
        #expect(loadingStore.loadState == .unavailable)
        let refresh = Task { await loadingStore.refresh() }
        while loader.callCount == 0 { await Task.yield() }
        #expect(loadingStore.loadState == .loading)
        loader.finishFirst()
        await refresh.value
        #expect(loadingStore.loadState == .loaded(isEmpty: true))

        let failingStore = DashboardStore { _ in throw URLError(.notConnectedToInternet) }
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
    }

    private func decodedResponse(
        timezone: String = "Asia/Tokyo",
        isEmpty: Bool = false
    ) throws -> DashboardResponse {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            DashboardResponse.self,
            from: Data(responseJSON(period: "4w", timezone: timezone, isEmpty: isEmpty).utf8)
        )
    }

    private func responseJSON(
        period: String,
        timezone: String = "Asia/Tokyo",
        isEmpty: Bool = false
    ) -> String {
        let currentPayments = isEmpty ? 0 : 2
        let currencies = isEmpty
            ? "[]"
            : "[{\"currency\":\"USD\",\"grossAmountMinor\":2700,\"averageAmountMinor\":1350}]"
        let comparedCurrencies = isEmpty
            ? "[]"
            : "[{\"currency\":\"USD\",\"currentAmountMinor\":2700,\"previousAmountMinor\":1000,\"comparison\":{\"state\":\"percent\",\"percent\":170}}]"
        let series = isEmpty
            ? "[]"
            : "[{\"start\":\"2026-09-02T15:00:00Z\",\"end\":\"2026-09-03T12:00:00Z\",\"payments\":2,\"amounts\":[{\"currency\":\"USD\",\"grossAmountMinor\":2700,\"averageAmountMinor\":1350}]}]"
        let products = isEmpty
            ? "[]"
            : "[{\"label\":\"Widget\",\"payments\":2,\"amounts\":[{\"currency\":\"USD\",\"grossAmountMinor\":2700,\"averageAmountMinor\":1350}]}]"
        let sources = isEmpty
            ? "[]"
            : "[{\"label\":\"Stripe\",\"payments\":2,\"amounts\":[{\"currency\":\"USD\",\"grossAmountMinor\":2700,\"averageAmountMinor\":1350}]}]"
        return """
        {
          "reportingTimezone": "\(timezone)",
          "generatedAt": "2026-09-03T12:00:00Z",
          "period": "\(period)",
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

    func load(_ period: DashboardPeriod) async throws -> DashboardResponse {
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
