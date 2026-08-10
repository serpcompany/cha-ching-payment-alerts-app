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
            PlaceholderView(
                title: "Connections",
                message: "Link Stripe, PayPal and Gumroad — more processors coming soon.",
                symbol: "link.circle.fill"
            )
            .tabItem { Label("Connect", systemImage: "link") }
            PlaceholderView(
                title: "Settings",
                message: "Pick your ping sound, craft your notification text, manage your plan.",
                symbol: "slider.horizontal.3"
            )
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
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
