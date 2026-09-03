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
            .navigationTitle(dailySummaryTitle)
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
                dailySummaryCarousel
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

    private var dailySummaryCarousel: some View {
        DailySummaryCarousel(
            selectedDayOffset: store.dayOffset,
            selectedCurrency: selectedCurrency,
            summary: { store.dailySummary(for: $0) },
            selectDayOffset: {
                await store.selectDayOffset($0)
                return store.dayOffset
            }
        )
        .padding(.horizontal, -16)
        .accessibilityLabel("Daily payment summaries")
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
                    comparison: dashboard.report.previous == nil ? nil : total?.comparison,
                    currentWindow: dashboard.report.current,
                    previousWindow: dashboard.report.previous,
                    reportingTimezone: dashboard.reportingTimezone
                )
                reportChart(
                    current: dashboard.report.currentSeries.map { ($0, $0.amounts.amount(for: selectedCurrency)) },
                    previous: dashboard.report.previousSeries.map { ($0, $0.amounts.amount(for: selectedCurrency)) },
                    label: "Gross volume",
                    reportingTimezone: dashboard.reportingTimezone,
                    valueLabel: { DashboardFormatting.money(minor: $0, currency: selectedCurrency) },
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
                    comparison: dashboard.report.previous == nil ? nil : dashboard.report.totals.payments.comparison,
                    currentWindow: dashboard.report.current,
                    previousWindow: dashboard.report.previous,
                    reportingTimezone: dashboard.reportingTimezone
                )
                reportChart(
                    current: dashboard.report.currentSeries.map { ($0, $0.payments) },
                    previous: dashboard.report.previousSeries.map { ($0, $0.payments) },
                    label: "Payments",
                    reportingTimezone: dashboard.reportingTimezone,
                    valueLabel: { $0.formatted() },
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

    private func reportValues(
        current: String,
        previous: String?,
        comparison: DashboardComparison?,
        currentWindow: DashboardWindow,
        previousWindow: DashboardWindow?,
        reportingTimezone: String
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                currentReportValue(current, window: currentWindow, timezone: reportingTimezone)
                Spacer()
                if let previous, let previousWindow {
                    previousReportValue(previous, window: previousWindow, timezone: reportingTimezone)
                }
                if let comparison { comparisonBadge(comparison) }
            }

            VStack(alignment: .leading, spacing: 12) {
                currentReportValue(current, window: currentWindow, timezone: reportingTimezone)
                if let previous, let previousWindow {
                    HStack(alignment: .firstTextBaseline) {
                        previousReportValue(previous, window: previousWindow, timezone: reportingTimezone)
                        Spacer()
                        if let comparison { comparisonBadge(comparison) }
                    }
                }
            }
        }
    }

    private func currentReportValue(
        _ value: String,
        window: DashboardWindow,
        timezone: String
    ) -> some View {
        VStack(alignment: .leading) {
            Text("Current").font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.bold())
            Text(windowLabel(window, timezone: timezone))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func previousReportValue(
        _ value: String,
        window: DashboardWindow,
        timezone: String
    ) -> some View {
        VStack(alignment: .trailing) {
            Text("Previous").font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline).foregroundStyle(.secondary)
            Text(windowLabel(window, timezone: timezone))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func comparisonBadge(_ comparison: DashboardComparison) -> some View {
        Text(comparison.text)
            .font(.caption.bold())
            .foregroundStyle(comparisonColor(comparison))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(comparisonColor(comparison).opacity(0.12), in: Capsule())
    }

    private func comparisonColor(_ comparison: DashboardComparison) -> Color {
        guard comparison.state != .none else { return .secondary }
        return (comparison.percent ?? 1) < 0 ? .red : Theme.accent
    }

    private func reportChart(
        current: [(bucket: DashboardBucket, value: Int)],
        previous: [(bucket: DashboardBucket, value: Int)],
        label: String,
        reportingTimezone: String,
        valueLabel: @escaping (Int) -> String,
        accessibilityLabel: String
    ) -> some View {
        Chart {
            ForEach(Array(previous.enumerated()), id: \.element.bucket.id) { index, point in
                LineMark(
                    x: .value("Period position", index),
                    y: .value(label, point.value),
                    series: .value("Series", "Previous")
                )
                .foregroundStyle(by: .value("Series", "Previous"))
                .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 5]))
            }
            ForEach(Array(current.enumerated()), id: \.element.bucket.id) { index, point in
                LineMark(
                    x: .value("Period position", index),
                    y: .value(label, point.value),
                    series: .value("Series", "Current")
                )
                .foregroundStyle(by: .value("Series", "Current"))
                .lineStyle(StrokeStyle(lineWidth: 3))

                PointMark(
                    x: .value("Period position", index),
                    y: .value(label, point.value)
                )
                .foregroundStyle(by: .value("Series", "Current"))
                .symbolSize(18)
            }
        }
        .chartForegroundStyleScale(["Current": Theme.accent, "Previous": Color.secondary.opacity(0.55)])
        .chartLegend(position: .bottom, alignment: .leading, spacing: 12)
        .chartXAxis {
            AxisMarks(values: chartAxisIndices(count: current.count)) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.16))
                AxisTick()
                AxisValueLabel {
                    if let index = value.as(Int.self), current.indices.contains(index) {
                        Text(chartDate(current[index].bucket.start, timezone: reportingTimezone))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.16))
                AxisValueLabel {
                    if let amount = value.as(Int.self) { Text(valueLabel(amount)) }
                }
            }
        }
        .chartXAxisLabel("Reporting date")
        .frame(maxWidth: .infinity)
        .frame(height: 180)
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

    private var dailySummaryTitle: String {
        guard let dashboard = store.dashboard else { return "Dashboard" }
        guard store.dayOffset > 0 else { return "Today" }
        let date = store.dailySummary(for: store.dayOffset)?.start
            ?? dateForRequestedOffset(store.dayOffset, from: dashboard)
        guard let timeZone = TimeZone(identifier: dashboard.reportingTimezone) else {
            return date.formatted(date: .abbreviated, time: .omitted)
        }
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
        style.timeZone = timeZone
        return date.formatted(style)
    }

    private func dateForRequestedOffset(_ requestedOffset: Int, from dashboard: DashboardResponse) -> Date {
        guard let timeZone = TimeZone(identifier: dashboard.reportingTimezone) else {
            return dashboard.dailySummary.start
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let offsetDifference = requestedOffset - dashboard.dayOffset
        return calendar.date(byAdding: .day, value: -offsetDifference, to: dashboard.dailySummary.start)
            ?? dashboard.dailySummary.start
    }

    private func chartAxisIndices(count: Int) -> [Int] {
        guard count > 1 else { return count == 1 ? [0] : [] }
        return Array(Set([0, count / 2, count - 1])).sorted()
    }

    private func chartDate(_ date: Date, timezone: String) -> String {
        var style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        style.timeZone = TimeZone(identifier: timezone) ?? .current
        return date.formatted(style)
    }

    private func windowLabel(_ window: DashboardWindow, timezone: String) -> String {
        "\(chartDate(window.start, timezone: timezone)) – \(chartDate(window.end, timezone: timezone))"
    }

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

#if DEBUG
struct DashboardPagingUITestFixture: View {
    @StateObject private var store: DashboardStore
    @StateObject private var preferences: PreferencesStore

    @MainActor
    init() {
        let preferences = PreferencesStore()
        preferences.setReportingTimezoneForUITesting("Asia/Tokyo")
        _preferences = StateObject(wrappedValue: preferences)
        _store = StateObject(wrappedValue: DashboardStore { _, dayOffset in
            if dayOffset > 0 {
                try await Task.sleep(for: .milliseconds(500))
            }
            if dayOffset == 2 {
                throw URLError(.notConnectedToInternet)
            }
            return Self.response(dayOffset: dayOffset)
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Dashboard day offset: \(store.dayOffset)")
                .accessibilityIdentifier("dashboard-paging-selected-offset")
            DashboardView()
                .environmentObject(store)
                .environmentObject(preferences)
        }
    }

    private static func response(dayOffset: Int) -> DashboardResponse {
        let day = Date(timeIntervalSince1970: 1_788_427_800 - TimeInterval(dayOffset * 86_400))
        let money = DashboardMoneyTotal(
            currency: "USD",
            payments: dayOffset + 1,
            grossAmountMinor: 59_110 + dayOffset * 37_230,
            averageAmountMinor: 59_110
        )
        let window = DashboardWindow(start: day.addingTimeInterval(-27 * 86_400), end: day)
        return DashboardResponse(
            reportingTimezone: "Asia/Tokyo",
            generatedAt: day,
            period: .fourWeeks,
            dayOffset: dayOffset,
            dailySummary: DashboardDailySummary(
                start: day,
                end: day.addingTimeInterval(86_400),
                payments: money.payments,
                currencies: [money]
            ),
            report: DashboardReport(
                current: window,
                previous: nil,
                totals: DashboardTotals(
                    payments: DashboardCountComparison(
                        current: money.payments,
                        previous: 0,
                        comparison: nil
                    ),
                    currencies: [DashboardCurrencyComparison(
                        currency: "USD",
                        currentAmountMinor: money.grossAmountMinor,
                        previousAmountMinor: 0,
                        comparison: nil
                    )]
                ),
                currentSeries: [],
                previousSeries: [],
                products: [],
                sources: []
            )
        )
    }
}

struct DashboardRefreshUITestFixture: View {
    @State private var completedRefreshCount = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    Text("Dashboard content")
                        .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
                        .padding()
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityIdentifier("dashboard-refresh-marker")
                        .accessibilityValue("Completed refreshes: \(completedRefreshCount)")

                    ForEach(0..<8) { row in
                        Text("Report row \(row)")
                            .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
                    }
                }
                .padding()
            }
            .accessibilityIdentifier("dashboard-refresh-scroll")
            .refreshable {
                defer { completedRefreshCount += 1 }
                try? await Task.sleep(for: .seconds(3))
            }
            .background(Theme.canvas.ignoresSafeArea())
            .navigationTitle("Today")
        }
    }
}
#endif
