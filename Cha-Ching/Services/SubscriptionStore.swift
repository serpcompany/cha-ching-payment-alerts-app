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
    case unavailable
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
    var currentEntitlement: (_ productID: String) async -> StorePurchase?
    var sync: () async throws -> Void
    var finish: (_ transactionID: UInt64) async -> Void
    var updates: () -> AsyncStream<StorePurchase>

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
        currentEntitlement: { productID in
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
        sync: { try await AppStore.sync() },
        finish: { transactionID in
            for await verification in Transaction.unfinished {
                guard case .verified(let transaction) = verification,
                      transaction.id == transactionID else { continue }
                await transaction.finish()
                return
            }
        },
        updates: {
            AsyncStream { continuation in
                let task = Task {
                    for await verification in Transaction.updates {
                        guard !Task.isCancelled,
                              case .verified(let transaction) = verification else { continue }
                        continuation.yield(StorePurchase(
                            signedTransaction: verification.jwsRepresentation,
                            transactionID: transaction.id
                        ))
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
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
    @Published private(set) var restoreMessage: String?

    private let accessClient: SubscriptionAccessClient
    private let storeKit: SubscriptionStoreKitClient
    private var status: SubscriptionStatus?
    private var updateTask: Task<Void, Never>?

    init(
        accessClient: SubscriptionAccessClient? = nil,
        storeKit: SubscriptionStoreKitClient? = nil
    ) {
        self.accessClient = accessClient ?? .live
        self.storeKit = storeKit ?? .live
    }

    func refresh() async {
        errorMessage = nil
        do {
            let status = try await accessClient.status()
            apply(status)
            guard status.access == .subscriptionRequired else { return }

            if let purchase = await storeKit.currentEntitlement(status.productId) {
                do {
                    try await reconcile(purchase)
                    if presentation == .fullAccess { return }
                } catch {
                    errorMessage = "Your current Apple subscription couldn't be verified by Cha-Ching."
                }
            }

            offer = try? await storeKit.offer(status.productId)
        } catch {
            presentation = .unavailable
            errorMessage = "Subscription status couldn't refresh."
        }
    }

    func startListeningForTransactions() {
        guard updateTask == nil else { return }
        updateTask = Task { [weak self, storeKit, accessClient] in
            for await purchase in storeKit.updates() {
                guard let self, !Task.isCancelled else { return }
                do {
                    let reconciled = try await accessClient.sync(purchase.signedTransaction)
                    apply(reconciled)
                    await storeKit.finish(purchase.transactionID)
                } catch {
                    errorMessage = "A subscription update couldn't be verified by Cha-Ching."
                }
            }
        }
    }

    func purchase() async {
        guard let status else { return }
        restoreMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            switch try await storeKit.purchase(status.productId, status.appAccountToken) {
            case .purchased(let purchase):
                try await reconcile(purchase)
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
        restoreMessage = nil
        errorMessage = nil
        guard status.access == .subscriptionRequired else {
            restoreMessage = "Your subscription is already active."
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            if let purchase = await storeKit.currentEntitlement(status.productId) {
                try await restore(purchase)
            } else {
                try await storeKit.sync()
                if let purchase = await storeKit.currentEntitlement(status.productId) {
                    try await restore(purchase)
                } else {
                    let refreshed = try await accessClient.status()
                    apply(refreshed)
                    restoreMessage = refreshed.access == .fullAccess
                        ? "Your subscription is already active."
                        : "No active purchases were found for this App Store account."
                }
            }
        } catch {
            if let apiError = error as? APIError {
                errorMessage = apiError.localizedDescription
            } else {
                let storeError = error as NSError
                errorMessage = "Purchases couldn't be restored. (\(storeError.domain) \(storeError.code))"
            }
        }
    }

    private func restore(_ purchase: StorePurchase) async throws {
        try await reconcile(purchase)
        restoreMessage = presentation == .fullAccess
            ? "Purchases restored."
            : "No active purchases were found for this App Store account."
    }

    private func reconcile(_ purchase: StorePurchase) async throws {
        let reconciled = try await accessClient.sync(purchase.signedTransaction)
        apply(reconciled)
        await storeKit.finish(purchase.transactionID)
    }

    func reset() {
        updateTask?.cancel()
        updateTask = nil
        status = nil
        offer = nil
        errorMessage = nil
        restoreMessage = nil
        presentation = .loading
    }

    private func apply(_ status: SubscriptionStatus) {
        self.status = status
        restoreMessage = nil
        switch status.access {
        case .fullAccess:
            offer = nil
            presentation = .fullAccess
        case .subscriptionRequired:
            presentation = .subscriptionRequired(action: status.action ?? .subscribeAgain)
        }
        errorMessage = nil
    }
}
