import SwiftUI

struct PaymentSourcesView: View {
    @EnvironmentObject private var connectStore: ConnectStore
    @EnvironmentObject private var notifications: NotificationManager
    @State private var destination: PaymentSourceDestination?
    @State private var routeAlert: PaymentSourceRouteAlert?

    var body: some View {
        ZStack {
                Theme.canvas.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        header
                        ForEach(connectStore.connections) { state in
                            ProviderCard(
                                state: state,
                                isAvailable: connectStore.isAvailable(state.provider)
                            ) { destination = .provider(state.provider) }
                            .accessibilityIdentifier("paymentSources.provider.\(state.provider.rawValue)")
                        }
                        ForEach(connectStore.customSources) { source in
                            CustomSourceCard(source: source) {
                                destination = .customSource(source.id)
                            }
                            .accessibilityIdentifier("paymentSources.custom.\(source.id)")
                        }
                        addCustomSourceCard
                    }
                    .padding(16)
                }
            }
        .navigationTitle("Payment sources")
        .refreshable { await connectStore.refresh() }
        .sheet(item: $destination) { destination in
            switch destination {
            case .provider(let provider):
                let state = connectStore.connections.first { $0.provider == provider }
                ConnectSheet(
                    provider: provider,
                    isConnected: state?.isConnected ?? false,
                    isActive: state?.isActive ?? false
                )
            case .newCustomSource:
                CustomSourceSheet(sourceID: nil)
            case .customSource(let id):
                CustomSourceSheet(sourceID: id)
            }
        }
        .task { await connectStore.refresh() }
        .task(id: notifications.openedCustomSourceID) {
            guard let sourceID = notifications.openedCustomSourceID else { return }
            await resolveNotificationSource(sourceID)
        }
        .alert(item: $routeAlert) { alert in
            switch alert {
            case .retry(let sourceID):
                Alert(
                    title: Text("Payment source couldn't load"),
                    message: Text("Check your connection and try again."),
                    primaryButton: .default(Text("Retry")) {
                        Task { await resolveNotificationSource(sourceID) }
                    },
                    secondaryButton: .cancel()
                )
            case .missing:
                Alert(
                    title: Text("Payment source unavailable"),
                    message: Text("This payment source no longer exists or isn't available to this account."),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Connect your payment sources")
                .font(.title3.bold())
                .foregroundStyle(Theme.ink)
            Text("Use Stripe or PayPal, or add any system that can send payment data to a webhook.")
                .font(.subheadline)
                .foregroundStyle(Theme.ink.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func resolveNotificationSource(_ sourceID: String) async {
        switch await connectStore.resolveCustomSourceRoute(id: sourceID) {
        case .found(let resolvedID):
            destination = .customSource(resolvedID)
            notifications.consumeOpenedCustomSource(sourceID)
        case .missing:
            routeAlert = .missing
            notifications.consumeOpenedCustomSource(sourceID)
        case .failed:
            routeAlert = .retry(sourceID)
        }
    }

    private var addCustomSourceCard: some View {
        Button { destination = .newCustomSource } label: {
            HStack(spacing: 14) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Connect another payment source")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text("Works with any store or service that can send a webhook")
                        .font(.caption)
                        .foregroundStyle(Theme.ink.opacity(0.55))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .cardStyle(padding: 0)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("paymentSources.add")
    }
}

private enum PaymentSourceRouteAlert: Identifiable {
    case retry(String)
    case missing

    var id: String {
        switch self {
        case .retry(let id): "retry-\(id)"
        case .missing: "missing"
        }
    }
}

enum PaymentSourceDestination: Identifiable {
    case provider(Provider)
    case newCustomSource
    case customSource(String)

    var id: String {
        switch self {
        case .provider(let provider): "provider-\(provider.rawValue)"
        case .newCustomSource: "custom-new"
        case .customSource(let id): "custom-\(id)"
        }
    }
}

private struct CustomSourceCard: View {
    let source: CustomPaymentSource
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 48, height: 48)
                    .background(Theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 3) {
                    Text(source.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text(source.displayedStatusTitle)
                        .font(.caption)
                        .foregroundStyle(source.needsAttention ? Theme.gold : source.connectionState == .active ? Theme.accent : .secondary)
                }
                Spacer()
                Image(systemName: source.needsAttention ? "exclamationmark.triangle.fill" : source.connectionState == .active ? "checkmark.circle.fill" : "chevron.right")
                    .foregroundStyle(source.needsAttention ? Theme.gold : source.connectionState == .active ? Theme.accent : .secondary)
            }
            .padding(14)
            .cardStyle(padding: 0)
        }
        .buttonStyle(.plain)
    }
}

private struct ProviderCard: View {
    let state: ConnectionState
    let isAvailable: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(state.provider.color.opacity(0.16))
                        .frame(width: 48, height: 48)
                    Image(systemName: state.provider.symbol)
                        .foregroundStyle(state.provider.color)
                        .font(.system(size: 20, weight: .semibold))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(state.provider.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(state.isActive ? Theme.accent : state.isConnected ? Theme.gold : Theme.ink.opacity(0.5))
                }
                Spacer()
                statusBadge
            }
            .padding(14)
            .cardStyle(padding: 0)
        }
        .buttonStyle(.plain)
    }

    private var statusText: String {
        if state.isConnected { return state.isActive ? (state.accountLabel ?? "Connected") : "Payments paused" }
        return isAvailable ? "Not connected" : "Setup in progress"
    }

    private var statusBadge: some View {
        Group {
            if state.isConnected && state.isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.accent)
            } else if state.isConnected {
                Image(systemName: "pause.circle.fill")
                    .foregroundStyle(Theme.gold)
            } else if !isAvailable {
                Text("Soon")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Theme.gold.opacity(0.14), in: Capsule())
                    .foregroundStyle(Theme.gold)
            } else {
                Text("Connect")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Theme.accent.opacity(0.14), in: Capsule())
                    .foregroundStyle(Theme.accent)
            }
        }
        .font(.title3)
    }
}
