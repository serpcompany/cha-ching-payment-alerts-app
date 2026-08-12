import Foundation
import StoreKitTest
import Testing
@testable import Cha_Ching

struct LocalStoreKitIntegrationTests {
    @Test @MainActor func annualSubscriptionCanBePurchasedAndRestoredLocally() async throws {
        let session = try SKTestSession(configurationFileNamed: "ChaChing")
        session.disableDialogs = true
        session.clearTransactions()

        let token = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let required = SubscriptionStatus(
            access: .subscriptionRequired,
            action: .startFreeTrial,
            appAccountToken: token,
            productId: "com.serpcompany.chaching.annual"
        )
        let granted = SubscriptionStatus(
            access: .fullAccess,
            action: nil,
            appAccountToken: token,
            productId: required.productId
        )
        var submittedTransactions: [String] = []
        let accessClient = SubscriptionAccessClient(
            status: { required },
            sync: { signedTransaction in
                submittedTransactions.append(signedTransaction)
                return granted
            }
        )

        let purchasingStore = SubscriptionStore(accessClient: accessClient, storeKit: .live)
        await purchasingStore.refresh()

        #expect(purchasingStore.offer?.displayPrice == "$14.99")
        #expect(purchasingStore.offer?.isEligibleForTrial == true)

        await purchasingStore.purchase()

        #expect(purchasingStore.presentation == .fullAccess)
        #expect(submittedTransactions.count == 1)

        let restoringStore = SubscriptionStore(accessClient: accessClient, storeKit: .live)
        await restoringStore.refresh()
        await restoringStore.restore()

        #expect(restoringStore.presentation == .fullAccess)
        #expect(submittedTransactions.count == 2)
    }

    @Test(
        .enabled(if: ProcessInfo.processInfo.environment["RUN_LOCAL_STOREKIT_E2E"] == "1")
    )
    @MainActor func purchaseAndRestoreReconcileWithTheLoopbackWorkerAndD1() async throws {
        let session = try SKTestSession(configurationFileNamed: "ChaChing")
        session.disableDialogs = true
        session.clearTransactions()
        APIClient.shared.clearAuthToken()
        try await APIClient.shared.signInForSimulatorDevelopment()
        #expect(try await APIClient.shared.validateSession())

        let purchasingStore = SubscriptionStore()
        await purchasingStore.refresh()
        #expect(purchasingStore.presentation == .subscriptionRequired(action: .startFreeTrial))
        await purchasingStore.purchase()

        #expect(purchasingStore.presentation == .fullAccess)
        #expect(purchasingStore.errorMessage == nil)

        let restoringStore = SubscriptionStore()
        await restoringStore.refresh()
        await restoringStore.restore()

        #expect(restoringStore.presentation == .fullAccess)
        #expect(restoringStore.errorMessage == nil)
    }
}
