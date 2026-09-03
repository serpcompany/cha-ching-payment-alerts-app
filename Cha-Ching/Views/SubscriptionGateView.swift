import SwiftUI

struct SubscriptionGateView: View {
    @EnvironmentObject private var subscription: SubscriptionStore
    @EnvironmentObject private var auth: AuthManager
    @State private var accountSheet: AccountSheet?
    @State private var isConfirmingPurchase = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 32)
                Image("BrandMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 112, height: 112)
                    .accessibilityHidden(true)
                VStack(spacing: 8) {
                    Text("Know the moment you get paid.")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.ink)
                    Text("Connect Stripe or a custom webhook and receive real payment alerts.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                VStack(spacing: 12) {
                    if let offer = subscription.offer, isEligibleForTrial {
                        Text("7 days free")
                            .font(.title2.bold())
                            .foregroundStyle(Theme.accent)
                        Text("Then \(offer.displayPrice) per year")
                            .font(.headline)
                    } else if let offer = subscription.offer {
                        Text("\(offer.displayPrice) per year")
                            .font(.title2.bold())
                    } else {
                        ProgressView("Loading localized price…")
                    }
                    Text(renewalDisclosure)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .cardStyle(padding: 20)

                primaryAction
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(subscription.isWorking || subscription.offer == nil)

                Button("Restore Purchases") {
                    Task { await subscription.restore() }
                }
                .disabled(subscription.isWorking)

                if let message = subscription.restoreMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if let error = subscription.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 18) {
                    Link("Support", destination: ChaChingLink.support)
                    Link("Terms", destination: ChaChingLink.terms)
                    Link("Privacy", destination: ChaChingLink.privacy)
                }
                .font(.footnote)

                HStack(spacing: 18) {
                    Button("Sign out") { auth.signOut() }
                    Button("Delete account", role: .destructive) {
                        auth.accountDeletionError = nil
                        accountSheet = .deletion
                    }
                }
                .font(.footnote)
            }
            .padding(24)
        }
        .background(Theme.canvas.ignoresSafeArea())
        .sheet(item: $accountSheet) { _ in
            AccountDeletionView()
        }
        .alert(purchaseConfirmationTitle, isPresented: $isConfirmingPurchase) {
            Button("Continue to Apple") {
                Task { await subscription.purchase() }
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text(purchaseConfirmationMessage)
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        if action == .updateBilling {
            Link("Update billing", destination: ChaChingLink.manageSubscription)
        } else {
            Button(primaryActionTitle) {
                isConfirmingPurchase = true
            }
        }
    }

    private var action: SubscriptionAction {
        if case .subscriptionRequired(let action) = subscription.presentation { return action }
        return .subscribeAgain
    }

    private var isEligibleForTrial: Bool {
        action == .startFreeTrial && subscription.offer?.isEligibleForTrial == true
    }

    private var primaryActionTitle: String {
        if isEligibleForTrial { return "Start 7-day free trial" }
        return action == .subscribeAgain ? "Subscribe again" : "Subscribe"
    }

    private var renewalDisclosure: String {
        if isEligibleForTrial {
            return "No charge today. After 7 days, your Apple Account will be charged \(displayPrice) for one year. The subscription renews annually unless canceled at least 24 hours before the current period ends."
        }
        return "Your Apple Account will be charged \(displayPrice) for one year. The subscription renews annually unless canceled at least 24 hours before the current period ends."
    }

    private var purchaseConfirmationTitle: String {
        isEligibleForTrial ? "Start your 7-day free trial?" : "Confirm annual subscription"
    }

    private var purchaseConfirmationMessage: String {
        if isEligibleForTrial {
            return "You won't be charged today. After 7 days, your Apple Account will be charged \(displayPrice) for one year. The subscription then renews annually unless canceled at least 24 hours before the current period ends."
        }
        return "Your Apple Account will be charged \(displayPrice) for one year. The subscription renews annually unless canceled at least 24 hours before the current period ends."
    }

    private var displayPrice: String {
        subscription.offer?.displayPrice ?? "the displayed price"
    }
}

#if DEBUG
@MainActor
private final class SubscriptionPurchaseProbe: ObservableObject {
    @Published var invocationCount = 0
}

struct SubscriptionConsentUITestFixture: View {
    @StateObject private var auth: AuthManager
    @StateObject private var probe: SubscriptionPurchaseProbe
    @StateObject private var subscription: SubscriptionStore

    @MainActor
    init() {
        let probe = SubscriptionPurchaseProbe()
        let action: SubscriptionAction = ProcessInfo.processInfo.environment["SUBSCRIPTION_CONSENT_ACTION"]
            == SubscriptionAction.subscribeAgain.rawValue
            ? .subscribeAgain
            : .startFreeTrial
        let status = SubscriptionStatus(
            access: .subscriptionRequired,
            action: action,
            appAccountToken: UUID(uuidString: "62B8F821-D8E3-41C8-AE10-0DAB0129B114")!,
            productId: "com.serpcompany.chaching.annual"
        )
        _auth = StateObject(wrappedValue: AuthManager())
        _probe = StateObject(wrappedValue: probe)
        _subscription = StateObject(wrappedValue: SubscriptionStore(
            accessClient: SubscriptionAccessClient(
                status: { status },
                sync: { _ in status }
            ),
            storeKit: SubscriptionStoreKitClient(
                offer: { _ in SubscriptionOffer(
                    displayPrice: "$14.99",
                    isEligibleForTrial: action == .startFreeTrial
                ) },
                purchase: { _, _ in
                    probe.invocationCount += 1
                    return .cancelled
                },
                currentEntitlement: { _ in nil },
                sync: {},
                finish: { _ in },
                updates: { AsyncStream { $0.finish() } }
            )
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Purchase invocations: \(probe.invocationCount)")
                .accessibilityIdentifier("subscription-purchase-invocations")
            SubscriptionGateView()
                .environmentObject(subscription)
                .environmentObject(auth)
        }
        .task { await subscription.refresh() }
    }
}
#endif

struct SubscriptionUnavailableView: View {
    @EnvironmentObject private var subscription: SubscriptionStore

    var body: some View {
        ContentUnavailableView {
            Label("Subscription status unavailable", systemImage: "exclamationmark.triangle")
        } description: {
            Text(subscription.errorMessage ?? "Cha-Ching couldn't verify access right now.")
        } actions: {
            Button("Try Again") { Task { await subscription.refresh() } }
                .buttonStyle(.borderedProminent)
        }
    }
}
