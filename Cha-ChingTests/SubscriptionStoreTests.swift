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
        var currentEntitlementChecks = 0
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
            currentEntitlement: { _ in
                currentEntitlementChecks += 1
                return currentEntitlementChecks == 1 ? nil : purchase
            },
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
        #expect(store.restoreMessage == "Purchases restored.")
        #expect(!forcedSyncAttempted)
    }

    @Test @MainActor func refreshAutomaticallyReconcilesAnAvailableCurrentEntitlement() async {
        let token = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let purchase = StorePurchase(
            signedTransaction: "current-verified-apple-jws",
            transactionID: 303
        )
        var submittedTransaction: String?
        var finishedTransaction: UInt64?
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
                submittedTransaction = signedTransaction
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
            sync: { forcedSyncAttempted = true },
            finish: { finishedTransaction = $0 },
            updates: { AsyncStream { $0.finish() } }
        )
        let store = SubscriptionStore(accessClient: accessClient, storeKit: storeKit)

        await store.refresh()

        #expect(store.presentation == .fullAccess)
        #expect(store.errorMessage == nil)
        #expect(store.restoreMessage == nil)
        #expect(submittedTransaction == purchase.signedTransaction)
        #expect(finishedTransaction == purchase.transactionID)
        #expect(!forcedSyncAttempted)
    }

    @Test @MainActor func restoreExplainsWhenNoActivePurchaseExists() async {
        let token = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let required = SubscriptionStatus(
            access: .subscriptionRequired,
            action: .subscribeAgain,
            appAccountToken: token,
            productId: "com.serpcompany.chaching.annual"
        )
        let accessClient = SubscriptionAccessClient(
            status: { required },
            sync: { _ in required }
        )
        let storeKit = SubscriptionStoreKitClient(
            offer: { _ in SubscriptionOffer(displayPrice: "$14.99", isEligibleForTrial: false) },
            purchase: { _, _ in .cancelled },
            currentEntitlement: { _ in nil },
            sync: {},
            finish: { _ in },
            updates: { AsyncStream { $0.finish() } }
        )
        let store = SubscriptionStore(accessClient: accessClient, storeKit: storeKit)

        await store.refresh()
        await store.restore()

        #expect(store.presentation == .subscriptionRequired(action: .subscribeAgain))
        #expect(store.errorMessage == nil)
        #expect(store.restoreMessage == "No active purchases were found for this App Store account.")
    }

    @Test @MainActor func restoreConfirmsWhenBackendAccessIsAlreadyActive() async {
        let token = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let active = SubscriptionStatus(
            access: .fullAccess,
            action: nil,
            appAccountToken: token,
            productId: "com.serpcompany.chaching.annual"
        )
        let accessClient = SubscriptionAccessClient(
            status: { active },
            sync: { _ in active }
        )
        var storeKitAccessed = false
        let storeKit = SubscriptionStoreKitClient(
            offer: { _ in SubscriptionOffer(displayPrice: "$14.99", isEligibleForTrial: false) },
            purchase: { _, _ in .cancelled },
            currentEntitlement: { _ in
                storeKitAccessed = true
                return nil
            },
            sync: { storeKitAccessed = true },
            finish: { _ in },
            updates: { AsyncStream { $0.finish() } }
        )
        let store = SubscriptionStore(accessClient: accessClient, storeKit: storeKit)

        await store.refresh()
        await store.restore()

        #expect(store.presentation == .fullAccess)
        #expect(store.errorMessage == nil)
        #expect(store.restoreMessage == "Your subscription is already active.")
        #expect(!storeKitAccessed)
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
        #expect(store.restoreMessage == nil)
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
