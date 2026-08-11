import SwiftUI

struct SaleRow: View {
    let sale: Sale

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: sale.source.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(sale.source.color)
                .frame(width: 40, height: 40)
                .background(sale.source.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(sale.product)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text("\(sale.country) \(sale.source.attribution)")
                    .font(.caption)
                    .foregroundStyle(Theme.ink.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 3) {
                Text(sale.formattedAmount)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.accent)
                Text(Formatters.relative(sale.date))
                    .font(.caption2)
                    .foregroundStyle(Theme.ink.opacity(0.45))
            }
        }
        .cardStyle(padding: 12)
    }
}

struct SaleDetailView: View {
    let sale: Sale

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 8) {
                        Text(sale.formattedAmount)
                            .font(.system(size: 46, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(sale.product)
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 34)
                    .background(Theme.heroGradient, in: RoundedRectangle(cornerRadius: 26, style: .continuous))

                    VStack(spacing: 0) {
                        if sale.details.isEmpty {
                            detailRow("Payment source", sale.source.title)
                            divider
                            detailRow("Status", sale.source.attribution)
                            divider
                            detailRow("Country", sale.country)
                            divider
                            detailRow("Type", sale.isSubscription ? "Subscription" : "One-time")
                        } else {
                            ForEach(Array(sale.details.enumerated()), id: \.offset) { index, detail in
                                detailRow(detail.label, detail.value)
                                if index < sale.details.count - 1 { divider }
                            }
                        }
                        divider
                        detailRow("Date", sale.date.formatted(date: .abbreviated, time: .shortened))
                    }
                    .cardStyle(padding: 4)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Payment")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var divider: some View {
        Rectangle().fill(Theme.ink.opacity(0.07)).frame(height: 1).padding(.horizontal, 12)
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Theme.ink.opacity(0.55))
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
    }
}
