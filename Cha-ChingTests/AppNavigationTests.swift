import Testing
@testable import Cha_Ching

struct AppNavigationTests {
    @Test @MainActor func signedInNavigationUsesOnlyTheThreeUserDestinations() {
        #expect(AppTab.allCases.map(\.title) == ["Dashboard", "Connect", "Settings"])
    }

    @Test func dashboardContainsOnlyTheMVPRevenueSummaryAndPayments() {
        #expect(DashboardSection.allCases == [.revenueToday, .payments])
    }
}
