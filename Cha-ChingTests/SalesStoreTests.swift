import Foundation
import Testing
@testable import Cha_Ching

@MainActor
private final class ScriptedSalesLoader {
    var results: [Result<[Sale], Error>]

    init(results: [Result<[Sale], Error>]) {
        self.results = results
    }

    func load() throws -> [Sale] {
        try results.removeFirst().get()
    }
}

@MainActor
private final class ControlledSalesLoader {
    private(set) var callCount = 0
    private var pending: [CheckedContinuation<[Sale], Error>] = []

    func load() async throws -> [Sale] {
        callCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            pending.append(continuation)
        }
    }

    func failOldestIfMultipleRequestsExist() -> Bool {
        guard pending.count > 1 else { return false }
        pending.removeFirst().resume(throwing: URLError(.networkConnectionLost))
        return true
    }

    func succeedRemainingRequests() {
        let remaining = pending
        pending.removeAll()
        for continuation in remaining {
            continuation.resume(returning: [])
        }
    }
}

struct SalesStoreTests {
    @Test func aCustomPaymentPreservesEveryConfiguredDetailInOrder() throws {
        let response = Data(#"""
        {
          "sales": [{
            "id": "sale-custom",
            "provider": "custom",
            "amountMinor": 900,
            "currency": "USD",
            "productLabel": "Circle Video Downloader",
            "plan": null,
            "saleType": "new_sale",
            "countryCode": null,
            "isSubscription": false,
            "occurredAt": "2026-08-11T08:27:14.000Z",
            "notificationFields": [
              {"label": "Buyer Email", "value": "buyer@example.com"},
              {"label": "Product", "value": "Circle Video Downloader"},
              {"label": "Amount", "value": "$9.00"},
              {"label": "UTM Campaign", "value": "summer-launch"}
            ]
          }]
        }
        """#.utf8)

        let payment = try #require(SalesClient.decode(response).first)

        #expect(payment.details == [
            SaleDetail(label: "Buyer Email", value: "buyer@example.com"),
            SaleDetail(label: "Product", value: "Circle Video Downloader"),
            SaleDetail(label: "Amount", value: "$9.00"),
            SaleDetail(label: "UTM Campaign", value: "summer-launch")
        ])
        #expect(payment.cardSymbol == "dollarsign.circle.fill")
        #expect(payment.cardSubtitle == "Buyer Email: buyer@example.com")
    }

    @Test @MainActor func aPaymentRefreshFailurePreservesPaymentsAndIsDismissible() async {
        let payment = Sale(
            id: "sale",
            product: "Existing payment",
            amountMinor: 1_000,
            currency: "USD",
            source: .stripe,
            date: Date(timeIntervalSince1970: 1),
            isSubscription: false,
            countryCode: nil
        )
        let loader = ScriptedSalesLoader(results: [
            .success([payment]),
            .failure(URLError(.notConnectedToInternet))
        ])
        let store = SalesStore(client: SalesClient(load: { try loader.load() }))

        await store.refresh()
        await store.refresh()

        #expect(store.sales == [payment])
        #expect(store.errorMessage == "Payments couldn't refresh.")
        store.dismissLoadError()
        #expect(store.errorMessage == nil)
    }

    @Test @MainActor func overlappingRefreshesDoNotFlashAFalseError() async {
        let loader = ControlledSalesLoader()
        let store = SalesStore(client: SalesClient(load: { try await loader.load() }))

        let automaticRefresh = Task { await store.refresh() }
        for _ in 0..<100 where loader.callCount < 1 { await Task.yield() }
        let pullToRefresh = Task { await store.refresh() }
        for _ in 0..<100 where loader.callCount < 2 { await Task.yield() }

        let exposedOverlap = loader.failOldestIfMultipleRequestsExist()
        if exposedOverlap {
            await automaticRefresh.value
            #expect(store.errorMessage == nil)
        }

        #expect(loader.callCount == 1)
        #expect(store.errorMessage == nil)

        loader.succeedRemainingRequests()
        await automaticRefresh.value
        await pullToRefresh.value
    }
}
