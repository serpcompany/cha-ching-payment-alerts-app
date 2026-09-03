import SwiftUI

struct ConnectSheet: View {
    let provider: Provider
    let isConnected: Bool
    let isActive: Bool

    @EnvironmentObject private var connectStore: ConnectStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingClearHistory = false
    @State private var clearResultMessage: String?

    private var capabilities: ProviderConnectionCapabilities {
        ProviderConnectionCapabilities(provider: provider, isConnected: isConnected)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: provider.symbol)
                            .foregroundStyle(provider.color)
                            .font(.title3)
                        Text(provider.setupHint)
                            .font(.footnote)
                            .foregroundStyle(Theme.ink.opacity(0.7))
                    }
                }

                if capabilities.canConnect {
                    Section {
                        Button {
                            Task { await connect() }
                        } label: {
                            HStack {
                                Spacer()
                                if connectStore.isBusy {
                                    ProgressView()
                                } else {
                                    Text("Connect with \(provider.title)")
                                        .fontWeight(.semibold)
                                }
                                Spacer()
                            }
                        }
                        .disabled(
                            connectStore.isBusy ||
                            !connectStore.isEntitled(to: provider) ||
                            !connectStore.isAvailable(provider)
                        )
                        .accessibilityIdentifier("paymentSources.connect.\(provider.rawValue)")
                    }
                    if !connectStore.isEntitled(to: provider) {
                        Section {
                            Text("Your current plan doesn't include this connection.")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                    } else if !connectStore.isAvailable(provider) {
                        Section {
                            Text("We're finishing \(provider.title) setup. This connection will become available without an app update.")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                if let error = connectStore.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }

                if capabilities.canTogglePayments {
                    Section("Payments") {
                        Toggle("Receive payments", isOn: Binding(
                            get: {
                                connectStore.connections.first { $0.provider == provider }?.isActive
                                    ?? isActive
                            },
                            set: { active in
                                Task { await connectStore.setProviderActivity(provider: provider, active: active) }
                            }
                        ))
                        .accessibilityIdentifier("paymentSources.receivePayments.\(provider.rawValue)")
                        Text("Turn this off to stop new payments and notifications without disconnecting \(provider.title).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if capabilities.canClearHistory {
                            Button("Clear payment history", role: .destructive) {
                                confirmingClearHistory = true
                            }
                            .disabled(connectStore.isBusy)
                            .accessibilityIdentifier("paymentSources.clearHistory.stripe")
                            Text("Removes Stripe payments from Cha-Ching. Your Stripe connection stays in place.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        if let clearResultMessage {
                            Text(clearResultMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if capabilities.canDisconnect {
                        Section {
                            Button("Disconnect \(provider.title)", role: .destructive) {
                                Task {
                                    await connectStore.disconnect(provider: provider)
                                    dismiss()
                                }
                            }
                            .disabled(connectStore.isBusy)
                            .accessibilityIdentifier("paymentSources.disconnect.\(provider.rawValue)")
                        }
                    }
                }

                Section {
                    Text(connectionPrivacyCopy)
                        .font(.caption2)
                        .foregroundStyle(Theme.ink.opacity(0.5))
                }
            }
            .navigationTitle(provider.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .alert("Clear Stripe payment history?", isPresented: $confirmingClearHistory) {
                Button("Cancel", role: .cancel) {}
                Button("Clear history", role: .destructive) {
                    Task { await clearPaymentHistory() }
                }
            } message: {
                Text("Remove all Stripe payments from Payments? This can't be undone. Your Stripe connection and paused setting will stay unchanged.")
            }
        }
    }

    private func connect() async {
        let success = await connectStore.connect(provider: provider)
        if success { dismiss() }
    }

    private func clearPaymentHistory() async {
        guard let cleared = await connectStore.clearPayments(provider: provider) else { return }
        PaymentHistoryEvents.changed()
        clearResultMessage = cleared == 1 ? "1 payment removed." : "\(cleared) payments removed."
    }

    private var connectionPrivacyCopy: String {
        switch provider {
        case .stripe:
            "Authorization happens on Stripe. Cha-Ching requests read-only event and charge access, stores only the connected account ID, and cannot create or change payments."
        default:
            "Authorization happens on \(provider.title). Provider tokens are encrypted by Cha-Ching's backend and are never stored on this device."
        }
    }
}

struct ProviderConnectionCapabilities: Equatable {
    let canConnect: Bool
    let canConfigure = true
    let canTogglePayments: Bool
    let canClearHistory: Bool
    let canDisconnect: Bool

    init(provider: Provider, isConnected: Bool) {
        canConnect = !isConnected
        canTogglePayments = isConnected
        canClearHistory = isConnected && provider == .stripe
        canDisconnect = isConnected
    }
}
