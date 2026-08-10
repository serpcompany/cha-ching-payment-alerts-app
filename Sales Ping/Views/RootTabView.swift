import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Today", systemImage: "bolt.horizontal.fill") }
            PlaceholderView(
                title: "Sales History",
                message: "Every sale, searchable and filterable by processor, product and date.",
                symbol: "list.bullet.rectangle.portrait"
            )
            .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            ConnectView()
                .tabItem { Label("Connect", systemImage: "link") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var connectStore: ConnectStore

    var body: some View {
        NavigationStack {
            Form {
                Section("Plan access") {
                    entitlementRow("Stripe connection", enabled: connectStore.isEntitled(to: .stripe))
                    entitlementRow("PayPal connection", enabled: connectStore.isEntitled(to: .paypal))
                }
                Section {
                    Button("Sign out", role: .destructive) { auth.signOut() }
                }
            }
            .navigationTitle("Settings")
            .task { await connectStore.refresh() }
        }
    }

    private func entitlementRow(_ title: String, enabled: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            Image(systemName: enabled ? "checkmark.circle.fill" : "lock.fill")
                .foregroundStyle(enabled ? Theme.accent : .secondary)
        }
    }
}

struct PlaceholderView: View {
    let title: String
    let message: String
    let symbol: String

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()
                VStack(spacing: 18) {
                    ZStack {
                        Circle()
                            .fill(Theme.accent.opacity(0.14))
                            .frame(width: 116, height: 116)
                        Image(systemName: symbol)
                            .font(.system(size: 46, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    Text(title)
                        .font(.title2.bold())
                        .foregroundStyle(Theme.ink)
                    Text(message)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.ink.opacity(0.6))
                        .padding(.horizontal, 44)
                    Text("Coming next")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Theme.gold.opacity(0.18), in: Capsule())
                        .foregroundStyle(Theme.gold)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    RootTabView().environmentObject(SalesStore())
}
