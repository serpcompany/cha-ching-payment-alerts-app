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
    @Test @MainActor func unchangedHealthStillConfirmsThatRefreshCompleted() async throws {
        let refreshedAt = Date(timeIntervalSince1970: 1_786_521_600)
        let feedback = CustomSourceHealthRefreshFeedback(now: { refreshedAt })
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

        let refreshed = await feedback.refresh { detail }

        #expect(refreshed?.source.health == detail.source.health)
        #expect(feedback.state == .refreshed(at: refreshedAt))
        #expect(feedback.statusMessage == "Connection health refreshed.")
    }

    @Test @MainActor func failedRefreshPreservesHealthAndShowsNearbyFailure() async {
        let feedback = CustomSourceHealthRefreshFeedback()

        let replacement = await feedback.refresh {
            throw URLError(.notConnectedToInternet)
        }

        #expect(replacement == nil)
        #expect(feedback.state == .failed)
        #expect(feedback.statusMessage == "Connection health couldn't refresh. Try again.")
    }

    @Test @MainActor func refreshActionIdentifiesItselfWhileTheRequestIsRunning() async {
        let loader = SuspendedHealthRefresh()
        let feedback = CustomSourceHealthRefreshFeedback()

        let task = Task { await feedback.refresh { try await loader.load() } }
        for _ in 0..<100 where feedback.state != .refreshing { await Task.yield() }

        #expect(feedback.buttonTitle == "Refreshing connection health…")
        #expect(feedback.isRefreshing)

        loader.fail()
        _ = await task.value
    }
}
