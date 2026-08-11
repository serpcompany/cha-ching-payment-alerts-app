import SwiftUI

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
