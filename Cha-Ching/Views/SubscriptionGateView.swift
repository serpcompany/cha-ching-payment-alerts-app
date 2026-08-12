import SwiftUI

struct SubscriptionGateView: View {
    @EnvironmentObject private var subscription: SubscriptionStore

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
                    .disabled(subscription.isWorking)
                    .disabled(subscription.isWorking || subscription.offer == nil)

                Button("Restore Purchases") {
                    Task { await subscription.restore() }
                }
                .disabled(subscription.isWorking)

                if let error = subscription.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 18) {
                    Link("Terms", destination: URL(string: "https://cha-ching-api.serpcompany.workers.dev/terms")!)
                    Link("Privacy", destination: URL(string: "https://cha-ching-api.serpcompany.workers.dev/privacy")!)
                }
                .font(.footnote)
            }
            .padding(24)
        }
        .background(Theme.canvas.ignoresSafeArea())
    }

    @ViewBuilder
    private var primaryAction: some View {
        if action == .updateBilling {
            Link("Update billing", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
        } else {
            Button(primaryActionTitle) {
                Task { await subscription.purchase() }
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
        if isEligibleForTrial { return "Start free trial" }
        return action == .subscribeAgain ? "Subscribe again" : "Subscribe"
    }

    private var renewalDisclosure: String {
        if isEligibleForTrial {
            return "Full access during your trial. The subscription renews automatically unless canceled at least 24 hours before the current period ends."
        }
        return "Full access with an auto-renewing subscription. Cancel at least 24 hours before the current period ends to prevent renewal."
    }
}

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
