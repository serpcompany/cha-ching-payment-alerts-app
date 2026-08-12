import Foundation
import Testing
@testable import Cha_Ching

struct SubscriptionStoreTests {
    @Test @MainActor func restoreUsesAnAvailableVerifiedEntitlementBeforeForcingAppStoreSync() async {
        let token = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let purchase = StorePurchase(
            signedTransaction: "available-verified-apple-jws",
            transactionID: 202
        )
        var forcedSyncAttempted = false
        let accessClient = SubscriptionAccessClient(
            status: {
                SubscriptionStatus(
                    access: .subscriptionRequired,
                    action: .subscribeAgain,
                    appAccountToken: token,
                    productId: "com.serpcompany.chaching.annual"
                )
            },
            sync: { signedTransaction in
                #expect(signedTransaction == purchase.signedTransaction)
                return SubscriptionStatus(
                    access: .fullAccess,
                    action: nil,
                    appAccountToken: token,
                    productId: "com.serpcompany.chaching.annual"
                )
            }
        )
        let storeKit = SubscriptionStoreKitClient(
            offer: { _ in SubscriptionOffer(displayPrice: "$14.99", isEligibleForTrial: false) },
            purchase: { _, _ in .cancelled },
            currentEntitlement: { _ in purchase },
            sync: {
                forcedSyncAttempted = true
                throw TestRestoreError.forcedSyncFailed
            },
            finish: { _ in },
            updates: { AsyncStream { $0.finish() } }
        )
        let store = SubscriptionStore(accessClient: accessClient, storeKit: storeKit)

        await store.refresh()
        await store.restore()

        #expect(store.presentation == .fullAccess)
        #expect(store.errorMessage == nil)
        #expect(!forcedSyncAttempted)
    }

    @Test @MainActor func restoreShowsTheStoreKitErrorCodeWhenForcedSyncFails() async {
        let token = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let accessClient = SubscriptionAccessClient(
            status: {
                SubscriptionStatus(
                    access: .subscriptionRequired,
                    action: .subscribeAgain,
                    appAccountToken: token,
                    productId: "com.serpcompany.chaching.annual"
                )
            },
            sync: { _ in Issue.record("No transaction should be submitted")
                return SubscriptionStatus(
                    access: .subscriptionRequired,
                    action: .subscribeAgain,
                    appAccountToken: token,
                    productId: "com.serpcompany.chaching.annual"
                )
            }
        )
        let storeKit = SubscriptionStoreKitClient(
            offer: { _ in SubscriptionOffer(displayPrice: "$14.99", isEligibleForTrial: false) },
            purchase: { _, _ in .cancelled },
            currentEntitlement: { _ in nil },
            sync: { throw NSError(domain: "ASDErrorDomain", code: 500) },
            finish: { _ in },
            updates: { AsyncStream { $0.finish() } }
        )
        let store = SubscriptionStore(accessClient: accessClient, storeKit: storeKit)

        await store.refresh()
        await store.restore()

        #expect(store.presentation == .subscriptionRequired(action: .subscribeAgain))
        #expect(store.errorMessage == "Purchases couldn't be restored. (ASDErrorDomain 500)")
    }

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
            currentEntitlement: { _ in nil },
            sync: {},
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

private enum TestRestoreError: Error {
    case forcedSyncFailed
}
