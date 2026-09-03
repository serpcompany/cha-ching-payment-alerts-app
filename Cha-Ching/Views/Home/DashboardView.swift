import Charts
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: DashboardStore
    @EnvironmentObject private var preferences: PreferencesStore

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    dashboardStateContent
                }
                .padding()
                .frame(maxWidth: .infinity)
            }
            .refreshable { await load() }
            .background(Theme.canvas.ignoresSafeArea())
            .navigationTitle("Home")
            .task { await load() }
        }
    }

    @ViewBuilder
    private var dashboardStateContent: some View {
        switch store.loadState {
        case .loading:
            ProgressView("Loading dashboard…")
                .frame(maxWidth: .infinity, minHeight: 520)
        case .loaded:
            if let dashboard = store.dashboard {
                if let error = store.errorMessage { refreshError(error) }
                DailySummaryCard(
                    summary: dashboard.dailySummary,
                    dayOffset: dashboard.dayOffset,
                    reportingTimezone: dashboard.reportingTimezone,
                    selectedCurrency: selectedCurrency,
                    isRefreshing: store.isRefreshing,
                    onPreviousDay: { Task { await store.selectPreviousDay() } },
                    onNextDay: { Task { await store.selectNextDay() } }
                )
                reportsHeader(dashboard)
                grossVolumeCard(dashboard)
                paymentsCard(dashboard)
                breakdownCard(title: "Payments by product", rows: dashboard.report.products)
                breakdownCard(title: "Payments by source", rows: dashboard.report.sources)
            }
        case .unavailable:
            ContentUnavailableView {
                Label("Dashboard unavailable", systemImage: "chart.xyaxis.line")
            } description: {
                Text("Cha-Ching couldn't load your payment overview.")
            } actions: {
                Button("Retry") { Task { await load() } }
            }
            .frame(maxWidth: .infinity, minHeight: 520)
        }
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
            let currencies = store.availableCurrencies
            if currencies.count > 1 {
                Picker("Currency", selection: Binding(
                    get: { selectedCurrency },
                    set: { store.selectCurrency($0) }
                )) {
                    ForEach(currencies, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
            }
        }
    }

    private func grossVolumeCard(_ dashboard: DashboardResponse) -> some View {
        let total = dashboard.report.totals.currencies.first { $0.currency == selectedCurrency }
        let currentAmounts = dashboard.report.currentSeries.map { $0.amounts.amount(for: selectedCurrency) }
        let previousAmounts = dashboard.report.previousSeries.map { $0.amounts.amount(for: selectedCurrency) }
        return GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                reportValues(
                    current: total.map { DashboardFormatting.money(minor: $0.currentAmountMinor, currency: $0.currency) } ?? "—",
                    previous: dashboard.report.previous == nil ? nil : total.map { DashboardFormatting.money(minor: $0.previousAmountMinor, currency: $0.currency) },
                    comparison: dashboard.report.previous == nil ? nil : total?.comparison
                )
                reportChart(
                    current: currentAmounts,
                    previous: previousAmounts,
                    label: "Gross volume",
                    accessibilityLabel: DashboardChartAccessibility.grossVolume(
                        current: currentAmounts,
                        previous: dashboard.report.previous == nil ? nil : previousAmounts,
                        currency: selectedCurrency
                    )
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
                    label: "Payments",
                    accessibilityLabel: DashboardChartAccessibility.payments(
                        current: dashboard.report.currentSeries.map(\.payments),
                        previous: dashboard.report.previous == nil
                            ? nil
                            : dashboard.report.previousSeries.map(\.payments)
                    )
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

    private func reportChart(
        current: [Int],
        previous: [Int],
        label: String,
        accessibilityLabel: String
    ) -> some View {
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
        .accessibilityLabel(accessibilityLabel)
    }

    private func breakdownCard(title: String, rows: [DashboardBreakdown]) -> some View {
        GroupBox(title) {
            if rows.isEmpty {
                ContentUnavailableView("No payments in this period", systemImage: "chart.bar")
                    .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        let selectedTotal = row.amounts.total(for: selectedCurrency)
                        LabeledContent {
                            VStack(alignment: .trailing) {
                                Text("\(selectedTotal?.payments ?? 0) payments")
                                Text(DashboardFormatting.money(minor: selectedTotal?.grossAmountMinor ?? 0, currency: selectedCurrency))
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

private struct DailySummaryMetric: Identifiable {
    let title: String
    let value: String
    var id: String { title }
}

private struct DailySummaryCard: View {
    let summary: DashboardDailySummary
    let dayOffset: Int
    let reportingTimezone: String
    let selectedCurrency: String
    let isRefreshing: Bool
    let onPreviousDay: () -> Void
    let onNextDay: () -> Void

    @GestureState private var dragTranslation = CGFloat.zero

    var body: some View {
        GroupBox {
            let money = summary.currencies.total(for: selectedCurrency)
            let metrics = [
                DailySummaryMetric(
                    title: "Gross volume",
                    value: money.map {
                        DashboardFormatting.money(minor: $0.grossAmountMinor, currency: $0.currency)
                    } ?? "—"
                ),
                DailySummaryMetric(title: "Payments", value: summary.payments.formatted()),
                DailySummaryMetric(
                    title: "Average payment",
                    value: money.map {
                        DashboardFormatting.money(minor: $0.averageAmountMinor, currency: $0.currency)
                    } ?? "—"
                )
            ]
            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 24) {
                        ForEach(metrics) { metric($0) }
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(metrics) { metric($0) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(dayOffset == 0 ? "Swipe left for previous days" : "Swipe left for earlier, right for newer")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        } label: {
            HStack(spacing: 10) {
                Button(action: onPreviousDay) {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("Previous day")
                .disabled(isRefreshing)

                Text(title)
                    .contentTransition(.numericText())

                Spacer()

                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Loading daily summary")
                }

                Button(action: onNextDay) {
                    Image(systemName: "chevron.right")
                }
                .accessibilityLabel("Next day")
                .disabled(dayOffset == 0 || isRefreshing)
            }
        }
        .contentShape(.rect)
        .offset(x: resistedDragTranslation)
        .animation(.interactiveSpring, value: dragTranslation)
        .simultaneousGesture(daySwipe)
        .accessibilityAction(named: "Previous day", onPreviousDay)
        .accessibilityAction(named: "Next day") {
            guard dayOffset > 0 else { return }
            onNextDay()
        }
    }

    private var title: String {
        guard dayOffset > 0 else { return "Today" }
        guard let timeZone = TimeZone(identifier: reportingTimezone) else {
            return summary.start.formatted(date: .abbreviated, time: .omitted)
        }
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
        style.timeZone = timeZone
        return summary.start.formatted(style)
    }

    private var resistedDragTranslation: CGFloat {
        if dayOffset == 0, dragTranslation > 0 { return dragTranslation * 0.15 }
        return dragTranslation * 0.35
    }

    private var daySwipe: some Gesture {
        DragGesture(minimumDistance: 20)
            .updating($dragTranslation) { value, state, _ in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                state = value.translation.width
            }
            .onEnded { value in
                guard !isRefreshing,
                      abs(value.translation.width) > abs(value.translation.height),
                      abs(value.predictedEndTranslation.width) >= 70
                else { return }
                if value.predictedEndTranslation.width < 0 {
                    onPreviousDay()
                } else if dayOffset > 0 {
                    onNextDay()
                }
            }
    }

    private func metric(_ metric: DailySummaryMetric) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(metric.title).font(.caption).foregroundStyle(.secondary)
            Text(metric.value).font(.title3.bold()).foregroundStyle(Theme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    DashboardView()
        .environmentObject(DashboardStore())
        .environmentObject(PreferencesStore())
}
