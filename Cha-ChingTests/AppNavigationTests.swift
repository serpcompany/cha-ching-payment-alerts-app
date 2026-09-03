import Foundation
import Testing
@testable import Cha_Ching

struct AppNavigationTests {
    @Test @MainActor func signedInNavigationUsesOnlyTheThreeUserDestinations() {
        #expect(AppTab.allCases.map(\.title) == ["Home", "Payments", "Settings"])
    }

    @Test func paymentSourcesAreASettingsDrillDown() {
        #expect(SettingsRoute.paymentSources != SettingsRoute.reportingTimezone)
    }

    @Test func paymentDeepLinkSelectsPaymentsWithoutASettingsPath() {
        let target = AppNavigation.target(openedSaleID: "sale", openedSourceID: nil)
        #expect(target == AppNavigationTarget(tab: .payments, settingsPath: []))
    }

    @Test func sourceHealthDeepLinkSelectsThePaymentSourceDrillDown() {
        let target = AppNavigation.target(openedSaleID: nil, openedSourceID: "source")
        #expect(target == AppNavigationTarget(tab: .settings, settingsPath: [.paymentSources]))
    }

    @Test func coldLaunchPaymentRouteFindsTheMatchingPaymentDetail() throws {
        let payments = [
            Sale(
                id: "other",
                product: "Other",
                amountMinor: 100,
                currency: "USD",
                source: .stripe,
                date: .distantPast,
                isSubscription: false,
                countryCode: nil
            ),
            Sale(
                id: "opened",
                product: "Opened",
                amountMinor: 200,
                currency: "USD",
                source: .custom,
                date: .now,
                isSubscription: false,
                countryCode: nil
            )
        ]

        let path = PaymentsNavigation.path(for: .found(payments[1]))
        #expect(path?.map(\.id) == ["opened"])
        #expect(PaymentsNavigation.path(for: .missing)?.isEmpty == true)
        #expect(PaymentsNavigation.path(for: .failed) == nil)
    }

    @Test func paymentSourceControlsRemainReachableForEachConnectionState() {
        #expect(PaymentSourceDestination.newCustomSource.id == "custom-new")
        #expect(PaymentSourceDestination.provider(.stripe).id == "provider-stripe")
        #expect(PaymentSourceDestination.customSource("source").id == "custom-source")

        let disconnected = ProviderConnectionCapabilities(provider: .stripe, isConnected: false)
        #expect(disconnected.canConnect)
        #expect(disconnected.canConfigure)
        #expect(!disconnected.canTogglePayments)
        #expect(!disconnected.canClearHistory)
        #expect(!disconnected.canDisconnect)

        let stripe = ProviderConnectionCapabilities(provider: .stripe, isConnected: true)
        #expect(!stripe.canConnect)
        #expect(stripe.canConfigure)
        #expect(stripe.canTogglePayments)
        #expect(stripe.canClearHistory)
        #expect(stripe.canDisconnect)

        let paypal = ProviderConnectionCapabilities(provider: .paypal, isConnected: true)
        #expect(paypal.canTogglePayments)
        #expect(!paypal.canClearHistory)
        #expect(paypal.canDisconnect)
    }
}
