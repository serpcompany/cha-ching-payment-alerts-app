import SwiftUI

enum Theme {
    /// Cha-Ching electric mint — the instant-success signal.
    static let accent = adaptive(light: (0.10, 0.68, 0.46), dark: (0.22, 0.90, 0.64))
    /// Warm coin gold — celebration without looking like a bank.
    static let gold = adaptive(light: (0.87, 0.56, 0.08), dark: (0.96, 0.73, 0.26))
    static let midnight = Color(red: 0.027, green: 0.082, blue: 0.133)
    static let ink = adaptive(light: (0.027, 0.082, 0.133), dark: (0.95, 1.0, 0.97))
    static let canvas = adaptive(light: (0.96, 0.98, 0.97), dark: (0.024, 0.063, 0.106))
    static let card = adaptive(light: (1.0, 1.0, 1.0), dark: (0.05, 0.11, 0.16))

    static let heroGradient = LinearGradient(
        colors: [midnight, Color(red: 0.04, green: 0.30, blue: 0.25), accent.opacity(0.90)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let signalGradient = LinearGradient(
        colors: [accent, gold],
        startPoint: .leading,
        endPoint: .trailing
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
