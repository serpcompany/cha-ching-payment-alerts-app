import SwiftUI
import Charts

struct HeroCard: View {
    let total: Double
    let count: Int
    let change: Double
    let notificationsEnabled: Bool

    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "dollarsign.circle.fill")
                Text("Revenue today")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                changeBadge
            }
            .foregroundStyle(.white.opacity(0.92))

            Text(Formatters.money(total))
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())

            HStack {
                Text("\(count) payment\(count == 1 ? "" : "s")")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                Label(notificationsEnabled ? "Notifications on" : "Notifications off",
                      systemImage: notificationsEnabled ? "bell.fill" : "bell.slash.fill")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.white.opacity(0.22), in: Capsule())
                    .foregroundStyle(.white)
            }
        }
        .padding(20)
        .background(Theme.heroGradient, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Image(systemName: "wave.3.right.circle.fill")
                .font(.system(size: 90))
                .foregroundStyle(.white.opacity(0.10))
                .offset(x: 18, y: -14)
                .scaleEffect(pulse ? 1.06 : 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: Theme.accent.opacity(0.28), radius: 16, x: 0, y: 10)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    private var changeBadge: some View {
        let up = change >= 0
        let pct = abs(change * 100).rounded()
        return Label("\(Int(pct))%", systemImage: up ? "arrow.up.right" : "arrow.down.right")
            .font(.caption.weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.white.opacity(0.2), in: Capsule())
            .foregroundStyle(.white)
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.ink.opacity(0.55))
            Text(value)
                .font(.headline)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

struct WeeklyChartCard: View {
    let data: [DayTotal]
    let weekTotal: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("This week")
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    Text(Formatters.money(weekTotal) + " collected")
                        .font(.caption)
                        .foregroundStyle(Theme.ink.opacity(0.55))
                }
                Spacer()
            }
            Chart(data) { point in
                BarMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Total", point.total),
                    width: .fixed(18)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(Theme.heroGradient)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(Theme.ink.opacity(0.08))
                    AxisValueLabel().foregroundStyle(Theme.ink.opacity(0.5))
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                        .foregroundStyle(Theme.ink.opacity(0.5))
                }
            }
            .frame(height: 150)
        }
        .cardStyle(padding: 18)
    }
}

struct NoSalesYetView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "cart.badge.questionmark")
                .font(.system(size: 40))
                .foregroundStyle(Theme.accent.opacity(0.7))
            Text("No payments yet")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Text("Keep the app connected — the moment someone buys, you'll hear the cha-ching.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.ink.opacity(0.55))
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .cardStyle(padding: 8)
    }
}
