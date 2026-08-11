import SwiftUI

@main
struct ChaChingApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = SalesStore()
    @StateObject private var auth = AuthManager()
    @StateObject private var connectStore = ConnectStore()
    @StateObject private var notifications = NotificationManager.shared
    @StateObject private var subscription = SubscriptionStore()

    var body: some Scene {
        WindowGroup {
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
                    }
                } else {
                    SignInView()
                }
            }
            .environmentObject(store)
            .environmentObject(auth)
            .environmentObject(connectStore)
            .environmentObject(notifications)
            .environmentObject(subscription)
            .tint(Theme.accent)
            .task(id: auth.isSignedIn) {
                notifications.clearAppBadge()
                if auth.isSignedIn {
                    await subscription.refresh()
                    guard subscription.presentation == .fullAccess else { return }
                    async let connections: Void = connectStore.refresh()
                    async let sales: Void = store.refresh()
                    _ = await (connections, sales)
                    notifications.registerIfAuthorized()
                }
            }
            .onChange(of: auth.isSignedIn) { _, isSignedIn in
                if !isSignedIn { subscription.reset() }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                notifications.clearAppBadge()
                guard auth.isSignedIn else { return }
                Task {
                    await subscription.refresh()
                    guard subscription.presentation == .fullAccess else { return }
                    await store.refresh()
                    notifications.registerIfAuthorized()
                }
            }
        }
    }
}
