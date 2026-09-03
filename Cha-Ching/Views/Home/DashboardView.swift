import Charts
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: DashboardStore
    @EnvironmentObject private var preferences: PreferencesStore

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading, store.dashboard == nil {
                    ProgressView("Loading dashboard…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let dashboard = store.dashboard {
                    dashboardContent(dashboard)
                } else {
                    ContentUnavailableView {
                        Label("Dashboard unavailable", systemImage: "chart.xyaxis.line")
                    } description: {
                        Text("Cha-Ching couldn't load your payment overview.")
                    } actions: {
                        Button("Retry") { Task { await load() } }
                    }
                }
            }
            .background(Theme.canvas.ignoresSafeArea())
            .navigationTitle("Home")
            .task { await load() }
        }
    }

    private func dashboardContent(_ dashboard: DashboardResponse) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if let error = store.errorMessage { refreshError(error) }
                todayCard(dashboard.today)
                reportsHeader(dashboard)
                grossVolumeCard(dashboard)
                paymentsCard(dashboard)
                breakdownCard(title: "Payments by product", rows: dashboard.report.products)
                breakdownCard(title: "Payments by source", rows: dashboard.report.sources)
            }
            .padding()
        }
        .refreshable { await store.refresh() }
    }

    private func todayCard(_ today: DashboardToday) -> some View {
        GroupBox("Today") {
            let money = today.currencies.first { $0.currency == selectedCurrency }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 24) {
                    metric("Gross volume", money.map { DashboardFormatting.money(minor: $0.grossAmountMinor, currency: $0.currency) } ?? "—")
                    metric("Payments", today.payments.formatted())
                    metric("Average payment", money.map { DashboardFormatting.money(minor: $0.averageAmountMinor, currency: $0.currency) } ?? "—")
                }
                VStack(alignment: .leading, spacing: 14) {
                    metric("Gross volume", money.map { DashboardFormatting.money(minor: $0.grossAmountMinor, currency: $0.currency) } ?? "—")
                    metric("Payments", today.payments.formatted())
                    metric("Average payment", money.map { DashboardFormatting.money(minor: $0.averageAmountMinor, currency: $0.currency) } ?? "—")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold()).foregroundStyle(Theme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func reportsHeader(_ dashboard: DashboardResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Reports overview").font(.title2.bold())
                Text(dashboard.reportingTimezone.replacingOccurrences(of: "_", with: " "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Report period", selection: Binding(
                get: { store.period },
                set: { period in Task { await store.selectPeriod(period) } }
            )) {
                ForEach(DashboardPeriod.allCases) { period in Text(period.title).tag(period) }
            }
            .pickerStyle(.menu)
            }
            let currencies = dashboard.report.totals.currencies.map(\.currency)
            if currencies.count > 1 {
                Picker("Currency", selection: Binding(
                    get: { selectedCurrency },
                    set: { store.selectedCurrency = $0 }
                )) {
                    ForEach(currencies, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private func grossVolumeCard(_ dashboard: DashboardResponse) -> some View {
        let total = dashboard.report.totals.currencies.first { $0.currency == selectedCurrency }
        return GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                reportValues(
                    current: total.map { DashboardFormatting.money(minor: $0.currentAmountMinor, currency: $0.currency) } ?? "—",
                    previous: dashboard.report.previous == nil ? nil : total.map { DashboardFormatting.money(minor: $0.previousAmountMinor, currency: $0.currency) },
                    comparison: dashboard.report.previous == nil ? nil : total?.comparison
                )
                reportChart(
                    current: dashboard.report.currentSeries.map { $0.amount(for: selectedCurrency) },
                    previous: dashboard.report.previousSeries.map { $0.amount(for: selectedCurrency) },
                    label: "Gross volume"
                )
            }
        } label: {
            Label("Gross volume", systemImage: "chart.line.uptrend.xyaxis")
        }
    }

    private func paymentsCard(_ dashboard: DashboardResponse) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                reportValues(
                    current: dashboard.report.totals.payments.current.formatted(),
                    previous: dashboard.report.previous == nil ? nil : dashboard.report.totals.payments.previous.formatted(),
                    comparison: dashboard.report.previous == nil ? nil : dashboard.report.totals.payments.comparison
                )
                reportChart(
                    current: dashboard.report.currentSeries.map(\.payments),
                    previous: dashboard.report.previousSeries.map(\.payments),
                    label: "Payments"
                )
            }
        } label: {
            Label("Payments", systemImage: "creditcard")
        }
    }

    private func reportValues(current: String, previous: String?, comparison: DashboardComparison?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading) {
                Text("Current").font(.caption).foregroundStyle(.secondary)
                Text(current).font(.title2.bold())
            }
            Spacer()
            if let previous {
                VStack(alignment: .trailing) {
                    Text("Previous").font(.caption).foregroundStyle(.secondary)
                    Text(previous).font(.headline).foregroundStyle(.secondary)
                }
            }
            if let comparison {
                Text(comparison.text)
                    .font(.caption.bold())
                    .foregroundStyle(comparisonColor(comparison))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(comparisonColor(comparison).opacity(0.12), in: Capsule())
            }
        }
    }

    private func comparisonColor(_ comparison: DashboardComparison) -> Color {
        guard comparison.state != .none else { return .secondary }
        return (comparison.percent ?? 1) < 0 ? .red : Theme.accent
    }

    private func reportChart(current: [Int], previous: [Int], label: String) -> some View {
        Chart {
            ForEach(Array(previous.enumerated()), id: \.offset) { index, value in
                LineMark(x: .value("Bucket", index), y: .value(label, value))
                    .foregroundStyle(.secondary.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
            ForEach(Array(current.enumerated()), id: \.offset) { index, value in
                LineMark(x: .value("Bucket", index), y: .value(label, value))
                    .foregroundStyle(Theme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 3))
            }
        }
        .chartXAxis(.hidden)
        .frame(height: 180)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) chart. Current total \(current.reduce(0, +)); previous total \(previous.reduce(0, +)).")
    }

    private func breakdownCard(title: String, rows: [DashboardBreakdown]) -> some View {
        GroupBox(title) {
            if rows.isEmpty {
                ContentUnavailableView("No payments in this period", systemImage: "chart.bar")
                    .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        LabeledContent {
                            VStack(alignment: .trailing) {
                                Text("\(row.payments) payments")
                                Text(DashboardFormatting.money(minor: row.amount(for: selectedCurrency), currency: selectedCurrency))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } label: {
                            Text(row.label)
                        }
                        .padding(.vertical, 8)
                        if index < rows.count - 1 { Divider() }
                    }
                }
            }
        }
    }

    private func refreshError(_ message: String) -> some View {
        GroupBox {
            HStack {
                Text(message).font(.subheadline)
                Spacer()
                Button("Retry") { Task { await load() } }
                Button("Dismiss") { store.dismissLoadError() }
            }
        }
    }

    private var selectedCurrency: String { store.selectedCurrency ?? "USD" }

    private func load() async {
        await preferences.initializeIfNeeded()
        guard preferences.reportingTimezone != nil else { return }
        await store.refresh()
    }
}

#Preview {
    DashboardView()
        .environmentObject(DashboardStore())
        .environmentObject(PreferencesStore())
}
