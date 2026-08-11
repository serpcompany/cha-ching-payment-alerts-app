import SwiftUI

enum DashboardSection: CaseIterable {
    case revenueToday
    case payments
}

struct HomeView: View {
    @EnvironmentObject private var store: SalesStore
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
                                 notificationsEnabled: notifications.canDeliverNotifications)
                        if let error = store.errorMessage {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .cardStyle(padding: 12)
                        }
                        recentSection
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 28)
                }
                .refreshable {
                    await store.refresh()
                }
            }
            .task {
                await store.refresh()
            }
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Image(systemName: notifications.canDeliverNotifications ? "bell.badge.fill" : "bell.slash.fill")
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Payments")
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
