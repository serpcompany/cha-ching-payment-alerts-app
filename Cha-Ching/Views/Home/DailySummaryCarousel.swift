import SwiftUI

struct DailySummaryPage: Identifiable {
    let id: Int
    let summary: DashboardDailySummary?
}

struct DailySummaryCarousel: View {
    let pages: [DailySummaryPage]
    let selectedCurrency: String
    @Binding var selection: Int?

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 12) {
                ForEach(pages) { page in
                    DailySummaryCard(summary: page.summary, selectedCurrency: selectedCurrency)
                        .containerRelativeFrame(.horizontal)
                        .accessibilityIdentifier("daily-summary-card.\(page.id)")
                        .id(page.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
        .scrollPosition(id: $selection, anchor: .center)
        .contentMargins(.horizontal, 16, for: .scrollContent)
    }
}

private struct DailySummaryMetric: Identifiable {
    let title: String
    let value: String
    var id: String { title }
}

private struct DailySummaryCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title3) private var contentHeight = 68.0
    @ScaledMetric(relativeTo: .title3) private var accessibilityContentHeight = 200.0
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
                ),
            ]
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(metrics) { metric in
                            VStack(alignment: .leading, spacing: 2) {
                                metricLabel(metric.title)
                                metricValue(metric.value)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                } else {
                    ViewThatFits(in: .horizontal) {
                        DailySummaryCompactMetrics(metrics: metrics, valueFont: .title3.bold())
                        DailySummaryCompactMetrics(metrics: metrics, valueFont: .body.bold())
                        DailySummaryCompactMetrics(metrics: metrics, valueFont: .subheadline.bold())
                        DailySummaryCompactMetrics(metrics: metrics, valueFont: .caption.bold())
                        DailySummaryCompactMetrics(
                            metrics: metrics,
                            valueFont: .caption2.bold(),
                            usesIntrinsicWidth: false
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(
                height: dynamicTypeSize.isAccessibilitySize
                    ? accessibilityContentHeight
                    : contentHeight,
                alignment: .center
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(metrics.map { "\($0.title), \($0.value)" }.joined(separator: ". "))
        }
        .accessibilityValue(summary == nil ? "Loading" : "Loaded")
    }

    private func metricLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func metricValue(_ value: String) -> some View {
        Text(value)
            .font(.title3.bold())
            .monospacedDigit()
            .foregroundStyle(Theme.ink)
    }
}

private struct DailySummaryCompactMetrics: View {
    let metrics: [DailySummaryMetric]
    let valueFont: Font
    var usesIntrinsicWidth = true

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 5) {
            GridRow {
                ForEach(metrics) { metric in
                    Text(metric.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: usesIntrinsicWidth, vertical: true)
                }
            }
            GridRow(alignment: .firstTextBaseline) {
                ForEach(metrics) { metric in
                    Text(metric.value)
                        .font(valueFont)
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: usesIntrinsicWidth, vertical: true)
                }
            }
        }
        .fixedSize(horizontal: usesIntrinsicWidth, vertical: false)
    }
}

#if DEBUG
struct SummaryCardUITestFixture: View {
    @State private var carouselPosition: Int?

    private var pages: [DailySummaryPage] {
        let allPages = [
            DailySummaryPage(id: 1, summary: DashboardDailySummary(
                start: Date(timeIntervalSince1970: 0),
                end: Date(timeIntervalSince1970: 1),
                payments: 2,
                currencies: [DashboardMoneyTotal(
                    currency: "USD", payments: 2, grossAmountMinor: 2_700, averageAmountMinor: 1_350
                )]
            )),
            DailySummaryPage(id: 2, summary: DashboardDailySummary(
                start: Date(timeIntervalSince1970: 0),
                end: Date(timeIntervalSince1970: 1),
                payments: 1_234_567,
                currencies: [DashboardMoneyTotal(
                    currency: "USD",
                    payments: 1_234_567,
                    grossAmountMinor: 123_456_789,
                    averageAmountMinor: 98_765_432
                )]
            )),
            DailySummaryPage(id: 0, summary: nil),
        ]
        guard let requestedID = ProcessInfo.processInfo.environment["SUMMARY_CARD_INITIAL_PAGE"]
            .flatMap(Int.init),
              let requestedIndex = allPages.firstIndex(where: { $0.id == requestedID })
        else { return allPages }
        return Array(allPages[requestedIndex...]) + Array(allPages[..<requestedIndex])
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                DailySummaryCarousel(
                    pages: pages,
                    selectedCurrency: "USD",
                    selection: $carouselPosition
                )
                .padding(.horizontal, -16)
            }
            .padding()
            .background(Theme.canvas.ignoresSafeArea())
            .navigationTitle("Summary cards")
        }
    }
}
#endif
