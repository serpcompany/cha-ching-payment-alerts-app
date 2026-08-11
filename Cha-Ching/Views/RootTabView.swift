import SwiftUI

enum AppTab: String, CaseIterable {
    case dashboard
    case connect
    case settings

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .connect: "Connect"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "chart.bar.fill"
        case .connect: "link"
        case .settings: "gearshape.fill"
        }
    }

    @MainActor @ViewBuilder
    var content: some View {
        switch self {
        case .dashboard: HomeView()
        case .connect: ConnectView()
        case .settings: SettingsView()
        }
    }
}

struct RootTabView: View {
    var body: some View {
        TabView {
            ForEach(AppTab.allCases, id: \.self) { tab in
                tab.content
                    .tabItem { Label(tab.title, systemImage: tab.systemImage) }
            }
        }
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var notifications: NotificationManager

    var body: some View {
        NavigationStack {
            Form {
                Section("Notifications") {
                    HStack {
                        Text("Payment notifications")
                        Spacer()
                        Text(notifications.statusText)
                            .foregroundStyle(notifications.canDeliverNotifications ? Theme.accent : .secondary)
                    }
                    if !notifications.isAuthorized {
                        Button("Enable notifications") {
                            Task { await notifications.requestPermissionAndRegister() }
                        }
                    } else if !notifications.canDeliverNotifications {
                        Button("Retry registration") {
                            notifications.registerIfAuthorized()
                        }
                    }
                    if let help = notifications.registrationHelpText {
                        Text(help).font(.footnote).foregroundStyle(.secondary)
                    }
                    if let error = notifications.registrationError {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }
                Section {
                    Button("Sign out", role: .destructive) { auth.signOut() }
                }
            }
            .navigationTitle("Settings")
            .task {
                await notifications.refreshAuthorizationStatus()
            }
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
