import Foundation
import Testing
@testable import Cha_Ching

@MainActor
private final class SuspendedHealthRefresh {
    private var continuation: CheckedContinuation<CustomSourceDetail, Error>?

    func load() async throws -> CustomSourceDetail {
        try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func fail() {
        continuation?.resume(throwing: URLError(.timedOut))
        continuation = nil
    }
}

struct CustomSourceHealthRefreshTests {
    @Test @MainActor func unchangedQuietHealthExplainsWhyItStillNeedsChecking() async throws {
        let refreshedAt = Date(timeIntervalSince1970: 1_786_521_600)
        let feedback = CustomSourceActivityCheckFeedback(now: { refreshedAt })
        let detail = CustomSourceDetail(
            source: CustomPaymentSource(
                id: "source-health",
                name: "SERP Store",
                status: .active,
                connectionState: .active,
                webhookUrl: URL(string: "https://example.com/webhook")!,
                createdAt: "2026-08-11 00:00:00",
                updatedAt: "2026-08-12 00:00:00",
                health: CustomSourceHealth(
                    status: .needsAttention,
                    reason: .quiet,
                    lastEventReceivedAt: "2026-08-11 23:00:00",
                    lastPaymentReceivedAt: "2026-08-11 23:00:00",
                    expectedEventBy: "2026-08-12 05:00:00",
                    detail: "No request has arrived within the expected activity window."
                )
            ),
            sample: nil,
            mapping: nil
        )

        let refreshed = await feedback.check(previousHealth: detail.source.health) { detail }

        #expect(refreshed?.source.health == detail.source.health)
        #expect(feedback.state == .checked(at: refreshedAt))
        #expect(feedback.statusMessage == "Still needs checking. No new webhook request has reached Cha-Ching.")
        #expect(feedback.statusDetail == "This does not prove the sender is disconnected. Verify the sender is using this webhook URL, then send or retry an event.")
        #expect(feedback.severity == .warning)
    }

    @Test @MainActor func failedRefreshPreservesHealthAndShowsNearbyFailure() async {
        let feedback = CustomSourceActivityCheckFeedback()

        let replacement = await feedback.check {
            throw URLError(.notConnectedToInternet)
        }

        #expect(replacement == nil)
        #expect(feedback.state == .failed)
        #expect(feedback.statusMessage == "Couldn't check for new webhook activity. Showing the last known status.")
        #expect(feedback.severity == .error)
    }

    @Test @MainActor func unchangedRejectedHealthExplainsHowToClearTheWarning() async {
        let feedback = CustomSourceActivityCheckFeedback()
        let detail = CustomSourceDetail(
            source: CustomPaymentSource(
                id: "source-rejected",
                name: "SERP Store",
                status: .active,
                connectionState: .active,
                webhookUrl: URL(string: "https://example.com/webhook")!,
                createdAt: "2026-08-11 00:00:00",
                updatedAt: "2026-08-12 00:00:00",
                health: CustomSourceHealth(
                    status: .needsAttention,
                    reason: .rejected,
                    lastEventReceivedAt: "2026-08-12 06:00:00",
                    lastPaymentReceivedAt: "2026-08-11 23:00:00",
                    expectedEventBy: nil,
                    detail: "Missing required mapped field."
                )
            ),
            sample: nil,
            mapping: nil
        )

        _ = await feedback.check(previousHealth: detail.source.health) { detail }

        #expect(feedback.statusMessage == "Still needs checking. No newer webhook request has arrived; the latest request was rejected.")
        #expect(feedback.statusDetail == "Missing required mapped field. Fix the sender payload, then resend it to this webhook URL.")
        #expect(feedback.severity == .warning)
    }

    @Test @MainActor func newActivityExplicitlyClearsThePreviousWarning() async {
        let feedback = CustomSourceActivityCheckFeedback()
        let previous = CustomSourceHealth(
            status: .needsAttention,
            reason: .quiet,
            lastEventReceivedAt: "2026-08-11 23:00:00",
            lastPaymentReceivedAt: "2026-08-11 23:00:00",
            expectedEventBy: "2026-08-12 05:00:00",
            detail: "No request has arrived within the expected activity window."
        )
        let newEventAt = "2026-08-12 07:30:00"
        let detail = CustomSourceDetail(
            source: CustomPaymentSource(
                id: "source-recovered",
                name: "SERP Store",
                status: .active,
                connectionState: .active,
                webhookUrl: URL(string: "https://example.com/webhook")!,
                createdAt: "2026-08-11 00:00:00",
                updatedAt: "2026-08-12 07:30:00",
                health: CustomSourceHealth(
                    status: .receiving,
                    reason: nil,
                    lastEventReceivedAt: newEventAt,
                    lastPaymentReceivedAt: newEventAt,
                    expectedEventBy: nil,
                    detail: "Cha-Ching received a webhook event."
                )
            ),
            sample: nil,
            mapping: nil
        )

        _ = await feedback.check(previousHealth: previous) { detail }

        #expect(feedback.statusMessage == "New webhook activity received. The previous warning is cleared.")
        #expect(feedback.statusDetail == "The latest request reached Cha-Ching. Its time is shown above.")
        #expect(feedback.severity == .positive)
    }

    @Test @MainActor func unchangedReceivingHealthReportsObservedActivityWithoutClaimingAProbe() async {
        let feedback = CustomSourceActivityCheckFeedback()
        let detail = healthDetail(status: .receiving, reason: nil)

        _ = await feedback.check(previousHealth: detail.source.health) { detail }

        #expect(feedback.statusMessage == "No newer webhook request has arrived.")
        #expect(feedback.statusDetail == "The most recent request shown above reached Cha-Ching. This check does not contact the sender.")
        #expect(feedback.severity == .positive)
    }

    @Test @MainActor func newerRejectedRequestIsReportedAsNewButStillUnhealthy() async {
        let feedback = CustomSourceActivityCheckFeedback()
        let previous = healthDetail(
            status: .needsAttention,
            reason: .rejected,
            lastEventReceivedAt: "2026-08-12 05:00:00"
        ).source.health
        let latest = healthDetail(
            status: .needsAttention,
            reason: .rejected,
            lastEventReceivedAt: "2026-08-12 06:00:00"
        )

        _ = await feedback.check(previousHealth: previous) { latest }

        #expect(feedback.statusMessage == "A newer webhook request arrived, but it was rejected.")
        #expect(feedback.severity == .warning)
    }

    @Test @MainActor func needsAttentionWithoutARecognizedReasonNeverLooksHealthy() async {
        let feedback = CustomSourceActivityCheckFeedback()
        let detail = healthDetail(status: .needsAttention, reason: nil)

        _ = await feedback.check(previousHealth: detail.source.health) { detail }

        #expect(feedback.statusMessage == "Still needs checking. Cha-Ching couldn't interpret the warning reason.")
        #expect(feedback.severity == .warning)
    }

    @Test @MainActor func unchangedAwaitingHealthSaysThatAnInboundEventIsRequired() async {
        let feedback = CustomSourceActivityCheckFeedback()
        let detail = healthDetail(status: .awaitingEvents, reason: nil, lastEventReceivedAt: nil)

        _ = await feedback.check { detail }

        #expect(feedback.statusMessage == "Still waiting. No webhook request has reached Cha-Ching.")
        #expect(feedback.statusDetail == "Send an event to this webhook URL, then check again.")
        #expect(feedback.severity == .informative)
    }

    @Test func pausedMonitoringDoesNotOfferAnActivityCheck() {
        let health = CustomSourceHealth(
            status: .paused,
            reason: nil,
            lastEventReceivedAt: "2026-08-12 06:00:00",
            lastPaymentReceivedAt: "2026-08-12 06:00:00",
            expectedEventBy: nil,
            detail: "Monitoring is paused while payment intake is paused."
        )

        #expect(!health.canCheckForNewActivity)
    }

    @Test @MainActor func acceptedDetailKeepsTheConnectCardHealthInSync() {
        let store = ConnectStore()
        let warning = healthDetail(status: .needsAttention, reason: .quiet).source
        let recovered = healthDetail(status: .receiving, reason: nil).source

        store.acceptCustomSourceDetail(CustomSourceDetail(source: warning, sample: nil, mapping: nil))
        store.acceptCustomSourceDetail(CustomSourceDetail(source: recovered, sample: nil, mapping: nil))

        #expect(store.customSources.count == 1)
        #expect(store.customSources.first?.health?.status == .receiving)
    }

    @Test @MainActor func refreshActionIdentifiesItselfWhileTheRequestIsRunning() async {
        let loader = SuspendedHealthRefresh()
        let feedback = CustomSourceActivityCheckFeedback()

        let task = Task { await feedback.check { try await loader.load() } }
        for _ in 0..<100 where feedback.state != .refreshing { await Task.yield() }

        #expect(feedback.buttonTitle == "Checking for new webhook activity…")
        #expect(feedback.isRefreshing)

        loader.fail()
        _ = await task.value
    }
}

private func healthDetail(
    status: CustomSourceHealth.Status,
    reason: CustomSourceHealth.Reason?,
    lastEventReceivedAt: String? = "2026-08-12 06:00:00"
) -> CustomSourceDetail {
    CustomSourceDetail(
        source: CustomPaymentSource(
            id: "source-health",
            name: "SERP Store",
            status: status == .paused ? .paused : .active,
            connectionState: status == .paused ? .paused : .active,
            webhookUrl: URL(string: "https://example.com/webhook")!,
            createdAt: "2026-08-11 00:00:00",
            updatedAt: "2026-08-12 06:00:00",
            health: CustomSourceHealth(
                status: status,
                reason: reason,
                lastEventReceivedAt: lastEventReceivedAt,
                lastPaymentReceivedAt: lastEventReceivedAt,
                expectedEventBy: nil,
                detail: status == .awaitingEvents
                    ? "No webhook event has been received yet."
                    : "Cha-Ching received a webhook event."
            )
        ),
        sample: nil,
        mapping: nil
    )
}
