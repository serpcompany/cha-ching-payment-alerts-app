import SwiftUI

struct DailySummaryCarousel: View {
    let selectedDayOffset: Int
    let selectedCurrency: String
    let summary: (Int) -> DashboardDailySummary?
    let selectDayOffset: (Int) async -> Int
    var forceDebouncedCommit = false
    @State private var selection: PageSlot?
    @State private var displayedDayOffset = 0
    @State private var pendingSelection: PageSlot?
    @State private var isScrollIdle = true
    @State private var isPaging = false
    @State private var fallbackCommitTask: Task<Void, Never>?

    private enum PageSlot: Int, Identifiable {
        case older
        case selected
        case newer

        var id: Self { self }
    }

    private var pageSlots: [PageSlot] {
        displayedDayOffset == 0 ? [.older, .selected] : [.older, .selected, .newer]
    }

    @ViewBuilder
    var body: some View {
        if #available(iOS 18.0, *), !forceDebouncedCommit {
            carousel
                .onScrollPhaseChange { _, newPhase in
                    isScrollIdle = newPhase == .idle
                    if isScrollIdle { commitPendingSelection() }
                }
        } else {
            carousel
        }
    }

    private var carousel: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 12) {
                // These semantic IDs never change while a gesture is active. The
                // represented dates change only after scrolling becomes idle and
                // the carousel recenters without animation.
                ForEach(pageSlots) { slot in
                    let dayOffset = dayOffset(for: slot)
                    DailySummaryCard(
                        pageID: dayOffset,
                        summary: summary(dayOffset),
                        selectedCurrency: selectedCurrency
                    )
                        .containerRelativeFrame(.horizontal)
                        .accessibilityIdentifier("daily-summary-card.\(dayOffset)")
                        .id(slot)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
        .scrollPosition(id: $selection, anchor: .center)
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .scrollDisabled(isPaging)
        .onAppear {
            displayedDayOffset = selectedDayOffset
            selection = .selected
        }
        .onChange(of: selectedDayOffset) { _, newOffset in
            guard !isPaging else { return }
            displayedDayOffset = newOffset
        }
        .onChange(of: selection) { _, requestedSlot in
            guard !isPaging,
                  let requestedSlot,
                  requestedSlot != .selected
            else { return }
            pendingSelection = requestedSlot
            if #available(iOS 18.0, *), !forceDebouncedCommit {
                if isScrollIdle { commitPendingSelection() }
            } else {
                scheduleFallbackCommit(for: requestedSlot)
            }
        }
        .onDisappear { fallbackCommitTask?.cancel() }
    }

    private func dayOffset(for slot: PageSlot) -> Int {
        switch slot {
        case .older: displayedDayOffset + 1
        case .selected: displayedDayOffset
        case .newer: displayedDayOffset - 1
        }
    }

    private func commitPendingSelection() {
        guard !isPaging,
              let requestedSlot = pendingSelection,
              requestedSlot != .selected
        else { return }
        pendingSelection = nil
        fallbackCommitTask?.cancel()
        let requestedOffset = dayOffset(for: requestedSlot)
        guard requestedOffset >= 0 else {
            recenter(on: displayedDayOffset)
            return
        }
        isPaging = true
        Task { @MainActor in
            let resolvedOffset = await selectDayOffset(requestedOffset)
            recenter(on: resolvedOffset)
            await Task.yield()
            isPaging = false
        }
    }

    private func scheduleFallbackCommit(for requestedSlot: PageSlot) {
        fallbackCommitTask?.cancel()
        fallbackCommitTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, selection == requestedSlot else { return }
            commitPendingSelection()
        }
    }

    private func recenter(on dayOffset: Int) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            displayedDayOffset = dayOffset
            selection = .selected
        }
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
    let pageID: Int
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
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(metric.title), \(metric.value)")
                            .accessibilityIdentifier(metricIdentifier(metric))
                        }
                    }
                } else {
                    DailySummaryCompactMetrics(metrics: metrics, pageID: pageID)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(
                height: dynamicTypeSize.isAccessibilitySize
                    ? accessibilityContentHeight
                    : contentHeight,
                alignment: .center
            )
            .accessibilityElement(children: .contain)
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

    private func metricIdentifier(_ metric: DailySummaryMetric) -> String {
        "daily-summary-metric.\(pageID).\(metric.title == "Payments" ? "payments" : "gross-volume")"
    }
}

private struct DailySummaryCompactMetrics: View {
    let metrics: [DailySummaryMetric]
    let pageID: Int

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(metrics) { metric in
                VStack(alignment: .center, spacing: 5) {
                    Text(metric.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ViewThatFits(in: .horizontal) {
                        fittedValue(metric.value, font: .title3.bold())
                        fittedValue(metric.value, font: .body.bold())
                        fittedValue(metric.value, font: .subheadline.bold())
                        fittedValue(metric.value, font: .caption.bold())
                        minimumScaleValue(metric.value)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(metric.title), \(metric.value)")
                .accessibilityIdentifier(metricIdentifier(metric))
            }
        }
    }

    private func fittedValue(_ value: String, font: Font) -> some View {
        Text(value)
            .font(font)
            .monospacedDigit()
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private func minimumScaleValue(_ value: String) -> some View {
        Text(value)
            .font(.caption2.bold())
            .monospacedDigit()
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity)
    }

    private func metricIdentifier(_ metric: DailySummaryMetric) -> String {
        "daily-summary-metric.\(pageID).\(metric.title == "Payments" ? "payments" : "gross-volume")"
    }
}

#if DEBUG
struct SummaryCardUITestFixture: View {
    @State private var selectedDayOffset: Int

    init() {
        let initialPage = ProcessInfo.processInfo.environment["SUMMARY_CARD_INITIAL_PAGE"]
            .flatMap(Int.init) ?? 1
        _selectedDayOffset = State(initialValue: initialPage)
    }

    private var summaries: [Int: DashboardDailySummary?] {
        [
            1: DashboardDailySummary(
                start: Date(timeIntervalSince1970: 0),
                end: Date(timeIntervalSince1970: 1),
                payments: 2,
                currencies: [DashboardMoneyTotal(
                    currency: "USD", payments: 2, grossAmountMinor: 2_700, averageAmountMinor: 1_350
                )]
            ),
            2: DashboardDailySummary(
                start: Date(timeIntervalSince1970: 0),
                end: Date(timeIntervalSince1970: 1),
                payments: 1_234_567,
                currencies: [DashboardMoneyTotal(
                    currency: "USD",
                    payments: 1_234_567,
                    grossAmountMinor: 123_456_789,
                    averageAmountMinor: 98_765_432
                )]
            ),
            0: nil,
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                DailySummaryCarousel(
                    selectedDayOffset: selectedDayOffset,
                    selectedCurrency: "USD",
                    summary: { summaries[$0] ?? nil },
                    selectDayOffset: {
                        selectedDayOffset = $0
                        return $0
                    }
                )
                .padding(.horizontal, -16)
            }
            .padding()
            .background(Theme.canvas.ignoresSafeArea())
            .navigationTitle("Summary cards")
        }
    }
}

struct SummaryPagingUITestFixture: View {
    @State private var selectedDayOffset = 0

    private var forceDebouncedCommit: Bool {
        ProcessInfo.processInfo.arguments.contains("-ui-testing-summary-paging-debounced")
    }

    private func summary(for offset: Int) -> DashboardDailySummary {
        DashboardDailySummary(
            start: Date(timeIntervalSince1970: TimeInterval(-offset * 86_400)),
            end: Date(timeIntervalSince1970: TimeInterval((1 - offset) * 86_400)),
            payments: offset,
            currencies: [DashboardMoneyTotal(
                currency: "USD",
                payments: offset,
                grossAmountMinor: offset * 100,
                averageAmountMinor: 100
            )]
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("Day offset: \(selectedDayOffset)")
                    .accessibilityIdentifier("summary-paging-selected-offset")
                ScrollView {
                    VStack(spacing: 24) {
                        DailySummaryCarousel(
                            selectedDayOffset: selectedDayOffset,
                            selectedCurrency: "USD",
                            summary: { summary(for: $0) },
                            selectDayOffset: { requestedOffset in
                                try? await Task.sleep(for: .milliseconds(20))
                                selectedDayOffset = requestedOffset
                                return requestedOffset
                            },
                            forceDebouncedCommit: forceDebouncedCommit
                        )
                        .padding(.horizontal, -16)

                        ForEach(0..<20, id: \.self) { row in
                            Text("Vertical row \(row)")
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle(selectedDayOffset == 0 ? "Today" : "Day \(selectedDayOffset)")
        }
    }
}
#endif
