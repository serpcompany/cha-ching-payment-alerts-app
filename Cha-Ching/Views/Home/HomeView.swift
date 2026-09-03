import SwiftUI

enum PaymentsNavigation {
    static func path(for resolution: NotificationSaleResolution) -> [Sale]? {
        switch resolution {
        case .found(let sale): [sale]
        case .missing: []
        case .failed: nil
        }
    }
}

struct PaymentsView: View {
    @EnvironmentObject private var store: SalesStore
    @EnvironmentObject private var notifications: NotificationManager
    @State private var path: [Sale] = []

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.canvas.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
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
            .task(id: notifications.openedSaleID) {
                guard let saleID = notifications.openedSaleID else { return }
                await store.refresh()
                let resolution = await store.resolveNotificationSale(id: saleID)
                guard let resolvedPath = PaymentsNavigation.path(for: resolution) else { return }
                path = resolvedPath
                notifications.consumeOpenedSale(saleID)
            }
            .navigationTitle("Payments")
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
            if let error = store.errorMessage {
                refreshError(error)
            }
            if store.sales.isEmpty {
                NoSalesYetView()
            } else {
                VStack(spacing: 10) {
                    ForEach(store.sales) { sale in
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

    private func refreshError(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Text("Check your connection, then try again.")
                .font(.footnote)
                .foregroundStyle(Theme.ink.opacity(0.65))
            HStack(spacing: 16) {
                Button("Retry") {
                    Task { await store.refresh() }
                }
                .fontWeight(.semibold)
                Button("Dismiss") {
                    store.dismissLoadError()
                }
            }
            .font(.footnote)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 14)
    }
}

enum Formatters {
    static func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    PaymentsView()
        .environmentObject(SalesStore())
        .environmentObject(ConnectStore())
        .environmentObject(NotificationManager.shared)
}
