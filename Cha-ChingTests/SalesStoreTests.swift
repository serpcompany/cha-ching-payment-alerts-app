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

struct SalesStoreTests {
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
}
