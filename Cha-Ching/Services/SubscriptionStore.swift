import Foundation
import StoreKit

enum SubscriptionAccess: String, Codable, Equatable {
    case fullAccess = "full_access"
    case subscriptionRequired = "subscription_required"
}

enum SubscriptionAction: String, Codable, Equatable {
    case startFreeTrial = "start_free_trial"
    case updateBilling = "update_billing"
    case subscribeAgain = "subscribe_again"
}

struct SubscriptionStatus: Codable, Equatable {
    let access: SubscriptionAccess
    let action: SubscriptionAction?
    let appAccountToken: UUID
    let productId: String
}

enum SubscriptionPresentation: Equatable {
    case loading
    case fullAccess
    case subscriptionRequired(action: SubscriptionAction)
}

struct SubscriptionOffer: Equatable {
    let displayPrice: String
    let isEligibleForTrial: Bool
}

struct StorePurchase {
    let signedTransaction: String
    let transactionID: UInt64
}

enum StorePurchaseOutcome {
    case purchased(StorePurchase)
    case pending
    case cancelled
}

@MainActor
struct SubscriptionAccessClient {
    var status: () async throws -> SubscriptionStatus
    var sync: (_ signedTransaction: String) async throws -> SubscriptionStatus

    static var live: SubscriptionAccessClient {
        SubscriptionAccessClient(
            status: { try await APIClient.shared.get("/v1/subscription") },
            sync: { signedTransaction in
                try await APIClient.shared.post(
                    "/v1/subscription/sync",
                    body: SignedTransactionRequest(signedTransaction: signedTransaction)
                )
            }
        )
    }
}

private struct SignedTransactionRequest: Encodable {
    let signedTransaction: String
}

@MainActor
struct SubscriptionStoreKitClient {
    var offer: (_ productID: String) async throws -> SubscriptionOffer
    var purchase: (_ productID: String, _ appAccountToken: UUID) async throws -> StorePurchaseOutcome
    var restore: (_ productID: String) async throws -> StorePurchase?
    var finish: (_ transactionID: UInt64) async -> Void

    static var live: SubscriptionStoreKitClient { SubscriptionStoreKitClient(
        offer: { productID in
            guard let product = try await Product.products(for: [productID]).first else {
                throw SubscriptionStoreError.productUnavailable
            }
            let isEligibleForTrial = await product.subscription?.isEligibleForIntroOffer ?? false
            return SubscriptionOffer(
                displayPrice: product.displayPrice,
                isEligibleForTrial: isEligibleForTrial
            )
        },
        purchase: { productID, appAccountToken in
            guard let product = try await Product.products(for: [productID]).first else {
                throw SubscriptionStoreError.productUnavailable
            }
            switch try await product.purchase(options: [.appAccountToken(appAccountToken)]) {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    throw SubscriptionStoreError.unverifiedTransaction
                }
                return .purchased(StorePurchase(
                    signedTransaction: verification.jwsRepresentation,
                    transactionID: transaction.id
                ))
            case .pending:
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .cancelled
            }
        },
        restore: { productID in
            try await AppStore.sync()
            for await verification in Transaction.currentEntitlements {
                guard case .verified(let transaction) = verification,
                      transaction.productID == productID else { continue }
                return StorePurchase(
                    signedTransaction: verification.jwsRepresentation,
                    transactionID: transaction.id
                )
            }
            return nil
        },
        finish: { transactionID in
            for await verification in Transaction.unfinished {
                guard case .verified(let transaction) = verification,
                      transaction.id == transactionID else { continue }
                await transaction.finish()
                return
            }
        }
    ) }
}

enum SubscriptionStoreError: LocalizedError {
    case productUnavailable
    case unverifiedTransaction

    var errorDescription: String? {
        switch self {
        case .productUnavailable: "The annual subscription is temporarily unavailable."
        case .unverifiedTransaction: "Apple couldn't verify this purchase."
        }
    }
}

@MainActor
final class SubscriptionStore: ObservableObject {
    @Published private(set) var presentation: SubscriptionPresentation = .loading
    @Published private(set) var offer: SubscriptionOffer?
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?

    private let accessClient: SubscriptionAccessClient
    private let storeKit: SubscriptionStoreKitClient
    private var status: SubscriptionStatus?

    init(
        accessClient: SubscriptionAccessClient? = nil,
        storeKit: SubscriptionStoreKitClient? = nil
    ) {
        self.accessClient = accessClient ?? .live
        self.storeKit = storeKit ?? .live
    }

    func refresh() async {
        do {
            let status = try await accessClient.status()
            apply(status)
            if status.access == .subscriptionRequired {
                offer = try? await storeKit.offer(status.productId)
            }
            errorMessage = nil
        } catch {
            presentation = .loading
            errorMessage = "Subscription status couldn't refresh."
        }
    }

    func purchase() async {
        guard let status else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            switch try await storeKit.purchase(status.productId, status.appAccountToken) {
            case .purchased(let purchase):
                let reconciled = try await accessClient.sync(purchase.signedTransaction)
                apply(reconciled)
                await storeKit.finish(purchase.transactionID)
            case .pending:
                errorMessage = "Apple is still processing this purchase."
            case .cancelled:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restore() async {
        guard let status else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            if let purchase = try await storeKit.restore(status.productId) {
                let reconciled = try await accessClient.sync(purchase.signedTransaction)
                apply(reconciled)
                await storeKit.finish(purchase.transactionID)
            } else {
                apply(try await accessClient.status())
            }
        } catch {
            errorMessage = "Purchases couldn't be restored."
        }
    }

    func reset() {
        status = nil
        offer = nil
        errorMessage = nil
        presentation = .loading
    }

    private func apply(_ status: SubscriptionStatus) {
        self.status = status
        switch status.access {
        case .fullAccess:
            presentation = .fullAccess
        case .subscriptionRequired:
            presentation = .subscriptionRequired(action: status.action ?? .subscribeAgain)
        }
        errorMessage = nil
    }
}
