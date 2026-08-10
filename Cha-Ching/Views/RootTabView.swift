import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Today", systemImage: "bolt.horizontal.fill") }
            SalesHistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            ConnectView()
                .tabItem { Label("Connect", systemImage: "link") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
    }
}

private struct SalesHistoryView: View {
    @EnvironmentObject private var store: SalesStore

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading && store.sales.isEmpty {
                    ProgressView("Loading verified sales…")
                } else if store.sales.isEmpty {
                    ContentUnavailableView(
                        "No verified sales yet",
                        systemImage: "creditcard",
                        description: Text("Connect Stripe and complete a payment to see it here.")
                    )
                } else {
                    List(store.sales) { sale in
                        NavigationLink(value: sale) { SaleRow(sale: sale) }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    .listStyle(.plain)
                    .refreshable { await store.refresh() }
                }
            }
            .navigationTitle("Sales History")
            .navigationDestination(for: Sale.self) { SaleDetailView(sale: $0) }
            .task { await store.refresh() }
        }
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var connectStore: ConnectStore
    @EnvironmentObject private var notifications: NotificationManager

    var body: some View {
        NavigationStack {
            Form {
                Section("Notifications") {
                    HStack {
                        Text("Payment pings")
                        Spacer()
                        Text(notifications.isEnabled ? "On" : "Off")
                            .foregroundStyle(notifications.isEnabled ? Theme.accent : .secondary)
                    }
                    if !notifications.isEnabled {
                        Button("Enable notifications") {
                            Task { await notifications.requestPermissionAndRegister() }
                        }
                    }
                    if let error = notifications.registrationError {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }
                Section("Plan access") {
                    entitlementRow("Stripe connection", enabled: connectStore.isEntitled(to: .stripe))
                    entitlementRow("PayPal connection", enabled: connectStore.isEntitled(to: .paypal))
                }
                Section {
                    Button("Sign out", role: .destructive) { auth.signOut() }
                }
            }
            .navigationTitle("Settings")
            .task {
                await connectStore.refresh()
                await notifications.refreshAuthorizationStatus()
            }
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

#Preview {
    RootTabView()
        .environmentObject(SalesStore())
        .environmentObject(AuthManager())
        .environmentObject(ConnectStore())
        .environmentObject(NotificationManager.shared)
}
