import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: SalesStore
    @EnvironmentObject private var connectStore: ConnectStore
    @EnvironmentObject private var notifications: NotificationManager

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        HeroCard(total: store.todayTotal,
                                 count: store.todaysSales.count,
                                 change: store.dayOverDayChange,
                                 notificationsEnabled: notifications.isEnabled)
                        if let error = store.errorMessage {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .cardStyle(padding: 12)
                        }
                        statRow
                        WeeklyChartCard(data: store.weeklyTotals, weekTotal: store.last7DaysTotal)
                        ConnectionsStrip(connections: connectStore.connections)
                        recentSection
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 28)
                }
                .refreshable {
                    async let sales: Void = store.refresh()
                    async let connections: Void = connectStore.refresh()
                    _ = await (sales, connections)
                }
            }
            .task {
                async let sales: Void = store.refresh()
                async let connections: Void = connectStore.refresh()
                _ = await (sales, connections)
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Image(systemName: notifications.isEnabled ? "bell.badge.fill" : "bell.slash.fill")
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    private var statRow: some View {
        HStack(spacing: 12) {
            StatTile(title: "Last 7 days",
                     value: Formatters.money(store.last7DaysTotal),
                     symbol: "calendar",
                     tint: Theme.accent)
            StatTile(title: "Top seller",
                     value: store.topProduct?.name ?? "—",
                     symbol: "flame.fill",
                     tint: Theme.gold)
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent pings")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("\(store.sales.count) total")
                    .font(.caption)
                    .foregroundStyle(Theme.ink.opacity(0.5))
            }
            if store.sales.isEmpty {
                NoSalesYetView()
            } else {
                VStack(spacing: 10) {
                    ForEach(store.sales.prefix(6)) { sale in
                        NavigationLink(value: sale) {
                            SaleRow(sale: sale)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationDestination(for: Sale.self) { SaleDetailView(sale: $0) }
    }
}

enum Formatters {
    static func money(_ value: Double, code: String = "USD") -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = code
        f.maximumFractionDigits = value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
        return f.string(from: NSNumber(value: value)) ?? "$0"
    }

    static func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    HomeView()
        .environmentObject(SalesStore())
        .environmentObject(ConnectStore())
        .environmentObject(NotificationManager.shared)
}
