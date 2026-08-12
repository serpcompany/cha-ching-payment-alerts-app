import Foundation
import Testing
@testable import Cha_Ching

struct AppNavigationTests {
    @Test @MainActor func signedInNavigationUsesOnlyTheThreeUserDestinations() {
        #expect(AppTab.allCases.map(\.title) == ["Dashboard", "Connect", "Settings"])
    }

    @Test func dashboardContainsOnlyTheMVPPaymentsSection() {
        #expect(DashboardSection.allCases == [.payments])
    }

    @Test func dashboardPresentsEveryLoadedPaymentInServerOrder() {
        let loadedPayments = (1...7).map { index in
            Sale(
                id: "payment-\(index)",
                product: "Product \(index)",
                amountMinor: index * 100,
                currency: "USD",
                source: .stripe,
                date: Date(timeIntervalSince1970: TimeInterval(8 - index)),
                isSubscription: false,
                countryCode: nil
            )
        }

        let displayedPayments = DashboardPaymentPresentation.rows(from: loadedPayments)

        #expect(displayedPayments.map(\.id) == [
            "payment-1",
            "payment-2",
            "payment-3",
            "payment-4",
            "payment-5",
            "payment-6",
            "payment-7"
        ])
    }
}
