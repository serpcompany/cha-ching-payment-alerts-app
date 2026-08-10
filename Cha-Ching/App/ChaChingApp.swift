import SwiftUI

@main
struct ChaChingApp: App {
    @StateObject private var store = SalesStore()
    @StateObject private var auth = AuthManager()
    @StateObject private var connectStore = ConnectStore()

    var body: some Scene {
        WindowGroup {
            Group {
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
            }
            .environmentObject(store)
            .environmentObject(auth)
            .environmentObject(connectStore)
            .tint(Theme.accent)
        }
    }
}
