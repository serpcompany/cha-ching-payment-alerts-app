import SwiftUI

@main
struct ChaChingApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = SalesStore()
    @StateObject private var auth = AuthManager()
    @StateObject private var connectStore = ConnectStore()
    @StateObject private var dashboard = DashboardStore()
    @StateObject private var notifications = NotificationManager.shared
    @StateObject private var preferences = PreferencesStore()
    @StateObject private var subscription = SubscriptionStore()

    var body: some Scene {
        WindowGroup {
            launchContent
        }
    }

    @ViewBuilder
    private var launchContent: some View {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-summary-cards") {
            SummaryCardUITestFixture()
                .tint(Theme.accent)
        } else if ProcessInfo.processInfo.arguments.contains("-ui-testing-dashboard-refresh") {
            DashboardRefreshUITestFixture()
                .tint(Theme.accent)
        } else {
            authenticatedContent
        }
#else
        authenticatedContent
#endif
    }

    private var authenticatedContent: some View {
        Group {
                if auth.isLoading {
                    ZStack {
                        Theme.canvas.ignoresSafeArea()
                        ProgressView()
                    }
                } else if auth.isSignedIn {
                    switch subscription.presentation {
                    case .loading:
                        ZStack {
                            Theme.canvas.ignoresSafeArea()
                            ProgressView()
                        }
                    case .fullAccess:
                        RootTabView()
                    case .subscriptionRequired:
                        SubscriptionGateView()
                    case .unavailable:
                        SubscriptionUnavailableView()
                    }
                } else {
                    SignInView()
                }
            }
            .environmentObject(store)
            .environmentObject(auth)
            .environmentObject(connectStore)
            .environmentObject(dashboard)
            .environmentObject(notifications)
            .environmentObject(preferences)
            .environmentObject(subscription)
            .tint(Theme.accent)
            .task(id: auth.isSignedIn) {
                notifications.clearAppBadge()
                if auth.isSignedIn {
                    subscription.startListeningForTransactions()
                    await subscription.refresh()
                }
            }
            .onChange(of: auth.isSignedIn) { _, isSignedIn in
                if !isSignedIn {
                    subscription.reset()
                    store.reset()
                    connectStore.reset()
                    dashboard.reset()
                    preferences.reset()
                }
            }
            .onChange(of: subscription.presentation) { _, presentation in
                guard presentation == .fullAccess else { return }
                Task {
                    await refreshFullAccessData()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                notifications.clearAppBadge()
                guard auth.isSignedIn else { return }
                Task {
                    await subscription.refresh()
                    guard subscription.presentation == .fullAccess else { return }
                    await refreshFullAccessData()
                }
        }
    }

    @MainActor
    private func refreshFullAccessData() async {
        await preferences.initializeIfNeeded()
        async let connections: Void = connectStore.refresh()
        async let sales: Void = store.refresh()
        async let dashboardRefresh: Void = dashboard.refresh()
        _ = await (connections, sales, dashboardRefresh)
        notifications.registerIfAuthorized()
    }
}
