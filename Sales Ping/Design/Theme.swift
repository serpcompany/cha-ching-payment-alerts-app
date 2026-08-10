import SwiftUI

enum Theme {
    /// Money green — energetic, confident, "you got paid".
    static let accent = adaptive(light: (0.02, 0.62, 0.42), dark: (0.16, 0.84, 0.58))
    /// Warm cash-register gold, used for highlights and the ping motif.
    static let gold = adaptive(light: (0.85, 0.58, 0.08), dark: (1.0, 0.76, 0.28))
    static let ink = adaptive(light: (0.07, 0.10, 0.12), dark: (0.96, 0.98, 0.97))
    static let canvas = adaptive(light: (0.96, 0.97, 0.96), dark: (0.05, 0.07, 0.07))
    static let card = adaptive(light: (1.0, 1.0, 1.0), dark: (0.10, 0.12, 0.12))

    static let heroGradient = LinearGradient(
        colors: [accent, accent.opacity(0.75), gold.opacity(0.75)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func adaptive(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(uiColor: UIColor { trait in
            let c = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }
}

struct CardBackground: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Theme.ink.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 6)
    }
}

extension View {
    func cardStyle(padding: CGFloat = 16) -> some View {
        modifier(CardBackground(padding: padding))
    }
}
