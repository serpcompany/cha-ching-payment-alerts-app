import SwiftUI

struct ConnectView: View {
    @EnvironmentObject private var connectStore: ConnectStore
    @State private var selectedProvider: Processor?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        header
                        ForEach(connectStore.connections) { state in
                            ProviderCard(state: state) { selectedProvider = state.processor }
                        }
                        moreComingCard
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Connect")
            .refreshable { await connectStore.refresh() }
        }
        .sheet(item: $selectedProvider) { provider in
            let state = connectStore.connections.first { $0.processor == provider }
            ConnectSheet(processor: provider, isConnected: state?.isConnected ?? false)
        }
        .task { await connectStore.refresh() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Link your payment providers")
                .font(.title3.bold())
                .foregroundStyle(Theme.ink)
            Text("Sales Ping listens for webhooks from each connected provider and pings your phone the moment money lands.")
                .font(.subheadline)
                .foregroundStyle(Theme.ink.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var moreComingCard: some View {
        VStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.title3)
                .foregroundStyle(Theme.gold)
            Text("More providers on the way")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Text("Have a processor we're missing? We're adding new ones based on requests.")
                .font(.caption)
                .foregroundStyle(Theme.ink.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .cardStyle()
    }
}

private struct ProviderCard: View {
    let state: ConnectionState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(state.processor.color.opacity(0.16))
                        .frame(width: 48, height: 48)
                    Image(systemName: state.processor.symbol)
                        .foregroundStyle(state.processor.color)
                        .font(.system(size: 20, weight: .semibold))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(state.processor.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text(state.isConnected ? (state.accountLabel ?? "Connected") : "Not connected")
                        .font(.caption)
                        .foregroundStyle(state.isConnected ? Theme.accent : Theme.ink.opacity(0.5))
                }
                Spacer()
                statusBadge
            }
            .padding(14)
            .cardStyle(padding: 0)
        }
        .buttonStyle(.plain)
    }

    private var statusBadge: some View {
        Group {
            if state.isConnected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.accent)
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
