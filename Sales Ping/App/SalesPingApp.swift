import SwiftUI

@main
struct SalesPingApp: App {
    @StateObject private var store = SalesStore()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(store)
                .tint(Theme.accent)
        }
    }
}
