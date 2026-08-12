import Foundation
import Testing
@testable import Cha_Ching

struct SubscriptionStoreTests {
    @Test @MainActor func aVerifiedStoreKitPurchaseDoesNotGrantAccessWithoutBackendApproval() async {
        let token = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        var submittedTransaction: String?
        let accessClient = SubscriptionAccessClient(
            status: {
                SubscriptionStatus(
                    access: .subscriptionRequired,
                    action: .startFreeTrial,
                    appAccountToken: token,
                    productId: "com.serpcompany.chaching.annual"
                )
            },
            sync: { signedTransaction in
                submittedTransaction = signedTransaction
                return SubscriptionStatus(
                    access: .subscriptionRequired,
                    action: .updateBilling,
                    appAccountToken: token,
                    productId: "com.serpcompany.chaching.annual"
                )
            }
        )
        let storeKit = SubscriptionStoreKitClient(
            offer: { _ in SubscriptionOffer(displayPrice: "$14.99", isEligibleForTrial: true) },
            purchase: { _, _ in .purchased(StorePurchase(
                signedTransaction: "verified-apple-jws",
                transactionID: 101
            )) },
            restore: { _ in nil },
            finish: { _ in },
            updates: { AsyncStream { $0.finish() } }
        )
        let store = SubscriptionStore(accessClient: accessClient, storeKit: storeKit)

        await store.refresh()
        await store.purchase()

        #expect(submittedTransaction == "verified-apple-jws")
        #expect(store.presentation == .subscriptionRequired(action: .updateBilling))
    }
}
