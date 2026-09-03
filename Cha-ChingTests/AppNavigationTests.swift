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
}
