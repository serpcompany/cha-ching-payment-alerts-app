import Charts
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: DashboardStore
    @EnvironmentObject private var preferences: PreferencesStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var carouselPosition: Int?

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
            .toolbar {
                if store.isRefreshing {
                    ToolbarItem(placement: .topBarTrailing) {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Loading daily summary")
                    }
                }
            }
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
        ScrollView(.horizontal) {
            LazyHStack(spacing: 12) {
                ForEach(store.carouselDayOffsets, id: \.self) { dayOffset in
                    DailySummaryCard(
                        summary: store.dailySummary(for: dayOffset),
                        selectedCurrency: selectedCurrency
                    )
                    .containerRelativeFrame(.horizontal, count: 10, span: 9, spacing: 12)
                    .id(dayOffset)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
        .scrollPosition(id: $carouselPosition, anchor: .center)
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .accessibilityLabel("Daily payment summaries")
        .onAppear { carouselPosition = store.dayOffset }
        .onChange(of: store.dayOffset) { _, newOffset in
            guard carouselPosition != newOffset else { return }
            updateCarouselPosition(newOffset)
        }
        .task(id: carouselPosition) {
            guard let requestedOffset = carouselPosition,
                  requestedOffset != store.dayOffset
            else { return }
            await store.selectDayOffset(requestedOffset)
            guard !Task.isCancelled, carouselPosition != store.dayOffset else { return }
            updateCarouselPosition(store.dayOffset)
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

    private func updateCarouselPosition(_ offset: Int) {
        if reduceMotion {
            carouselPosition = offset
        } else {
            withAnimation(.snappy) { carouselPosition = offset }
        }
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

private struct DailySummaryMetric: Identifiable {
    let title: String
    let value: String
    var id: String { title }
}

private struct DailySummaryCard: View {
    let summary: DashboardDailySummary?
    let selectedCurrency: String

    var body: some View {
        GroupBox {
            let money = summary?.currencies.total(for: selectedCurrency)
            let metrics = [
                DailySummaryMetric(
                    title: "Gross volume",
                    value: money.map {
                        DashboardFormatting.money(minor: $0.grossAmountMinor, currency: $0.currency)
                    } ?? "—"
                ),
                DailySummaryMetric(title: "Payments", value: summary?.payments.formatted() ?? "—"),
                DailySummaryMetric(
                    title: "Avg. $",
                    value: money.map {
                        DashboardFormatting.money(minor: $0.averageAmountMinor, currency: $0.currency)
                    } ?? "—"
                )
            ]
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    ForEach(metrics) { metric in
                        Text(metric.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    ForEach(metrics) { metric in
                        Text(metric.value)
                            .font(.title3.bold())
                            .foregroundStyle(Theme.ink)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(metrics.map { "\($0.title), \($0.value)" }.joined(separator: ". "))
        }
        .accessibilityValue(summary == nil ? "Loading" : "Loaded")
    }
}

#Preview {
    DashboardView()
        .environmentObject(DashboardStore())
        .environmentObject(PreferencesStore())
}
