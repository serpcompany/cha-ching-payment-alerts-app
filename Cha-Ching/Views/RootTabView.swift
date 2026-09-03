import SwiftUI
import UIKit

enum AppTab: String, CaseIterable {
    case home
    case payments
    case settings

    var title: String {
        switch self {
        case .home: "Home"
        case .payments: "Payments"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house.fill"
        case .payments: "creditcard.fill"
        case .settings: "gearshape.fill"
        }
    }
}

enum SettingsRoute: Hashable {
    case paymentSources
    case reportingTimezone
}

struct AppNavigationTarget: Equatable {
    let tab: AppTab
    let settingsPath: [SettingsRoute]
}

enum AppNavigation {
    static func target(openedSaleID: String?, openedSourceID: String?) -> AppNavigationTarget? {
        if openedSourceID != nil {
            return AppNavigationTarget(tab: .settings, settingsPath: [.paymentSources])
        }
        if openedSaleID != nil {
            return AppNavigationTarget(tab: .payments, settingsPath: [])
        }
        return nil
    }
}

struct NotificationRouteLifecycle {
    private var activeSaleID: String?
    private var activeSourceID: String?

    mutating func paymentTarget(for saleID: String?) -> AppNavigationTarget? {
        defer { activeSaleID = saleID }
        guard let saleID, saleID != activeSaleID else { return nil }
        return AppNavigation.target(openedSaleID: saleID, openedSourceID: nil)
    }

    mutating func sourceTarget(for sourceID: String?) -> AppNavigationTarget? {
        defer { activeSourceID = sourceID }
        guard let sourceID, sourceID != activeSourceID else { return nil }
        return AppNavigation.target(openedSaleID: nil, openedSourceID: sourceID)
    }
}

struct RootTabView: View {
    @EnvironmentObject private var dashboard: DashboardStore
    @EnvironmentObject private var notifications: NotificationManager
    @State private var selectedTab = AppTab.home
    @State private var settingsPath: [SettingsRoute] = []
    @State private var routeLifecycle = NotificationRouteLifecycle()

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem { Label(AppTab.home.title, systemImage: AppTab.home.systemImage) }
                .tag(AppTab.home)
            PaymentsView()
                .tabItem { Label(AppTab.payments.title, systemImage: AppTab.payments.systemImage) }
                .tag(AppTab.payments)
            SettingsView(path: $settingsPath)
                .tabItem { Label(AppTab.settings.title, systemImage: AppTab.settings.systemImage) }
                .tag(AppTab.settings)
        }
        .task(id: notifications.openedSaleID) {
            await routeOpenedPayment()
        }
        .task(id: notifications.openedCustomSourceID) {
            routeOpenedSource()
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

    private func applyNotificationRoute(_ target: AppNavigationTarget) {
        selectedTab = target.tab
        settingsPath = target.settingsPath
    }

    private func routeOpenedPayment() async {
        guard let target = routeLifecycle.paymentTarget(for: notifications.openedSaleID) else { return }
        applyNotificationRoute(target)
        await dashboard.refresh()
    }

    private func routeOpenedSource() {
        guard let target = routeLifecycle.sourceTarget(for: notifications.openedCustomSourceID) else { return }
        applyNotificationRoute(target)
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var notifications: NotificationManager
    @EnvironmentObject private var preferences: PreferencesStore
    @EnvironmentObject private var subscription: SubscriptionStore
    @Binding var path: [SettingsRoute]
    @State private var accountSheet: AccountSheet?

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section("Payment sources") {
                    NavigationLink(value: SettingsRoute.paymentSources) {
                        Label("Payment sources", systemImage: "link")
                    }
                    .accessibilityIdentifier("settings.paymentSources")
                }
                Section("Reporting") {
                    NavigationLink(value: SettingsRoute.reportingTimezone) {
                        LabeledContent("Timezone") {
                            Text(preferences.reportingTimezone?.replacingOccurrences(of: "_", with: " ") ?? "Setting up…")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let error = preferences.errorMessage {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }
                Section("Subscription") {
                    Text("Full access")
                    Button("Restore Purchases") {
                        Task { await subscription.restore() }
                    }
                    .disabled(subscription.isWorking)
                    if let message = subscription.restoreMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let error = subscription.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    Link(
                        "Manage Subscription",
                        destination: ChaChingLink.manageSubscription
                    )
                }
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
                    Button("Delete account", role: .destructive) {
                        auth.accountDeletionError = nil
                        accountSheet = .deletion
                    }
                }
                Section("Help and legal") {
                    Link("Support", destination: ChaChingLink.support)
                    Link("Privacy Policy", destination: ChaChingLink.privacy)
                    Link("Terms of Use", destination: ChaChingLink.terms)
                }
            }
            .navigationTitle("Settings")
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .paymentSources:
                    PaymentSourcesView()
                case .reportingTimezone:
                    ReportingTimezoneView()
                }
            }
            .task {
                await preferences.initializeIfNeeded()
                await notifications.refreshAuthorizationStatus()
            }
            .sheet(item: $accountSheet) { _ in
                AccountDeletionView()
            }
        }
    }
}

private struct ReportingTimezoneView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dashboard: DashboardStore
    @EnvironmentObject private var preferences: PreferencesStore
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var suggestedIdentifiers: [String] {
        unique([
            preferences.reportingTimezone,
            TimeZone.current.identifier,
            "UTC",
            "America/Los_Angeles",
            "America/Denver",
            "America/Chicago",
            "America/New_York",
            "Europe/London",
            "Europe/Berlin",
            "Asia/Tokyo",
            "Australia/Sydney",
        ].compactMap { $0 })
    }

    private var identifiers: [String] {
        let all = TimeZone.knownTimeZoneIdentifiers
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return all }
        return all.filter { identifier in
            identifier.localizedCaseInsensitiveContains(trimmedQuery)
                || displayName(for: identifier).localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search by city or timezone", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($searchFocused)
                }
            }

            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section("Suggested") {
                    ForEach(suggestedIdentifiers, id: \.self) { identifier in
                        timezoneButton(identifier)
                    }
                }
                Section("All timezones") {
                    ForEach(identifiers, id: \.self) { identifier in
                        timezoneButton(identifier)
                    }
                }
            } else {
                Section {
                    ForEach(identifiers, id: \.self) { identifier in
                        timezoneButton(identifier)
                    }
                }
                if identifiers.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
        .navigationTitle("Reporting timezone")
        .searchable(text: $query, prompt: "Search timezones")
        .task { searchFocused = true }
    }

    private func timezoneButton(_ identifier: String) -> some View {
        Button {
            Task {
                guard await preferences.updateReportingTimezone(identifier) else { return }
                await dashboard.reloadForReportingTimezoneChange()
                dismiss()
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName(for: identifier))
                        .foregroundStyle(.primary)
                    Text(identifier)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if preferences.reportingTimezone == identifier {
                    Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                }
            }
        }
        .disabled(preferences.isSaving)
    }

    private func displayName(for identifier: String) -> String {
        identifier
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "/", with: " / ")
    }

    private func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
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
        .environmentObject(DashboardStore())
        .environmentObject(PreferencesStore())
        .environmentObject(NotificationManager.shared)
        .environmentObject(SubscriptionStore())
}
