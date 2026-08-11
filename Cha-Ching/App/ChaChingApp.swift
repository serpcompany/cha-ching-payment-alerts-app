import SwiftUI

@main
struct ChaChingApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = SalesStore()
    @StateObject private var auth = AuthManager()
    @StateObject private var connectStore = ConnectStore()
    @StateObject private var notifications = NotificationManager.shared

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--notification-designer-review") {
                    WebhookNotificationDesignerReviewView()
                } else if auth.isLoading {
                    ZStack {
                        Theme.canvas.ignoresSafeArea()
                        ProgressView()
                    }
                } else if auth.isSignedIn {
                    RootTabView()
                } else {
                    SignInView()
                }
                #else
                if auth.isLoading {
                    ZStack {
                        Theme.canvas.ignoresSafeArea()
                        ProgressView()
                    }
                } else if auth.isSignedIn {
                    RootTabView()
                } else {
                    SignInView()
                }
                #endif
            }
            .environmentObject(store)
            .environmentObject(auth)
            .environmentObject(connectStore)
            .environmentObject(notifications)
            .tint(Theme.accent)
            .task(id: auth.isSignedIn) {
                if auth.isSignedIn {
                    async let connections: Void = connectStore.refresh()
                    async let sales: Void = store.refresh()
                    _ = await (connections, sales)
                    notifications.registerIfAuthorized()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, auth.isSignedIn else { return }
                Task {
                    await store.refresh()
                    notifications.registerIfAuthorized()
                }
            }
        }
    }
}
