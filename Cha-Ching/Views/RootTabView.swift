import SwiftUI
import UIKit

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
    @EnvironmentObject private var notifications: NotificationManager
    @State private var selectedTab = AppTab.dashboard

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                tab.content
                    .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                    .tag(tab)
            }
        }
        .onChange(of: notifications.openedSaleID) { _, saleID in
            if saleID != nil { selectedTab = .dashboard }
        }
        .onChange(of: notifications.openedCustomSourceID) { _, sourceID in
            if sourceID != nil { selectedTab = .connect }
        }
        .task(id: notifications.openedCustomSourceID) {
            if notifications.openedCustomSourceID != nil { selectedTab = .connect }
        }
        .sheet(item: foregroundNotificationBinding) { notification in
            ForegroundPaymentNotificationView(notification: notification)
        }
    }

    private var foregroundNotificationBinding: Binding<ForegroundPaymentNotification?> {
        Binding(
            get: { notifications.foregroundNotification },
            set: { value in
                if value == nil { notifications.dismissForegroundNotification() }
            }
        )
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var notifications: NotificationManager

    var body: some View {
        NavigationStack {
            Form {
                Section("Notifications") {
                    Toggle(
                        "Payment notifications",
                        isOn: Binding(
                            get: { notifications.paymentNotificationsEnabled },
                            set: { enabled in
                                Task { await notifications.setPaymentNotificationsEnabled(enabled) }
                            }
                        )
                    )
                    .disabled(notifications.isUpdatingPaymentNotifications)
                    if notifications.paymentNotificationsEnabled
                        && notifications.isAuthorized
                        && !notifications.canDeliverNotifications {
                        Button("Retry registration") {
                            notifications.registerIfAuthorized()
                        }
                    }
                    if notifications.paymentNotificationsEnabled
                        && notifications.authorizationStatus == .denied {
                        Button("Open iPhone Settings") {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                            UIApplication.shared.open(url)
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

private struct ForegroundPaymentNotificationView: View {
    @Environment(\.dismiss) private var dismiss
    let notification: ForegroundPaymentNotification

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    Label(notification.title, systemImage: "dollarsign.circle.fill")
                        .font(.title2.bold())
                        .foregroundStyle(Theme.accent)
                        .padding(.bottom, 4)
                    ForEach(Array(notification.lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, 4)
                        Divider()
                    }
                }
                .padding(20)
            }
            .background(Theme.canvas)
            .navigationTitle("Payment notification")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}

#Preview {
    RootTabView()
        .environmentObject(SalesStore())
        .environmentObject(AuthManager())
        .environmentObject(ConnectStore())
        .environmentObject(NotificationManager.shared)
}
