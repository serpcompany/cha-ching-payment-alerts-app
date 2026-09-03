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
            #expect(response.report.currentSeries.first?.amount(for: "USD") == 2700)
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
        var shouldFail = false
        let store = DashboardStore { _ in
            if shouldFail { throw URLError(.notConnectedToInternet) }
            return response
        }
        await store.refresh()
        let loadedAt = store.dashboard?.generatedAt
        shouldFail = true
        await store.refresh()

        #expect(store.dashboard?.generatedAt == loadedAt)
        #expect(store.errorMessage == "Dashboard couldn't refresh.")
        store.dismissLoadError()
        #expect(store.errorMessage == nil)
    }

    private func decodedResponse() throws -> DashboardResponse {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(DashboardResponse.self, from: Data(responseJSON(period: "4w").utf8))
    }

    private func responseJSON(period: String) -> String {
        """
        {
          "reportingTimezone": "Asia/Tokyo",
          "generatedAt": "2026-09-03T12:00:00Z",
          "period": "\(period)",
          "today": {
            "start": "2026-09-02T15:00:00Z",
            "end": "2026-09-03T12:00:00Z",
            "payments": 2,
            "currencies": [{"currency":"USD","grossAmountMinor":2700,"averageAmountMinor":1350}]
          },
          "report": {
            "current": {"start":"2026-08-06T15:00:00Z","end":"2026-09-03T12:00:00Z"},
            "previous": {"start":"2026-07-08T18:00:00Z","end":"2026-08-06T15:00:00Z"},
            "totals": {
              "payments": {"current":2,"previous":1,"comparison":{"state":"percent","percent":100}},
              "currencies": [{"currency":"USD","currentAmountMinor":2700,"previousAmountMinor":1000,"comparison":{"state":"percent","percent":170}}]
            },
            "currentSeries": [{"start":"2026-09-02T15:00:00Z","end":"2026-09-03T12:00:00Z","payments":2,"amounts":[{"currency":"USD","grossAmountMinor":2700,"averageAmountMinor":1350}]}],
            "previousSeries": [],
            "products": [{"label":"Widget","payments":2,"amounts":[{"currency":"USD","grossAmountMinor":2700,"averageAmountMinor":1350}]}],
            "sources": [{"label":"Stripe","payments":2,"amounts":[{"currency":"USD","grossAmountMinor":2700,"averageAmountMinor":1350}]}]
          }
        }
        """
    }
}
