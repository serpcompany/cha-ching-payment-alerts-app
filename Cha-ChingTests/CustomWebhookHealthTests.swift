import Foundation
import Testing
@testable import Cha_Ching

struct CustomWebhookHealthTests {
    @Test func rejectedRequestPresentsPassiveSenderSideResolution() {
        let health = CustomSourceHealth(
            status: .needsAttention,
            reason: .rejected,
            lastEventReceivedAt: "2026-08-12 06:00:00",
            lastPaymentReceivedAt: "2026-08-11 23:00:00",
            expectedEventBy: nil,
            detail: "The latest request did not include the mapped payment amount."
        )

        #expect(health.statusTitle == "Latest webhook request rejected")
        #expect(health.managementGuidance == "Fix the sender payload, then resend it to this webhook URL.")
    }

    @Test func activeSourceDecodesIndependentWebhookHealthEvidence() throws {
        let source = try JSONDecoder().decode(CustomPaymentSource.self, from: Data(#"""
        {
          "id": "source-quiet",
          "name": "SERP Store",
          "status": "active",
          "connectionState": "active",
          "webhookUrl": "https://example.test/private",
          "createdAt": "2026-08-11 00:00:00",
          "updatedAt": "2026-08-12 00:00:00",
          "health": {
            "status": "needs_attention",
            "reason": "quiet",
            "lastEventReceivedAt": "2026-08-12 05:00:00",
            "lastPaymentReceivedAt": "2026-08-12 05:00:00",
            "expectedEventBy": "2026-08-12T11:00:00.000Z",
            "detail": "No webhook requests arrived within this source's expected activity window."
          }
        }
        """#.utf8))

        #expect(source.status == .active)
        #expect(source.health?.status == .needsAttention)
        #expect(source.health?.reason == .quiet)
        #expect(source.health?.statusTitle == "No recent webhook activity")
        #expect(source.health?.managementGuidance == "This may be normal when there are no payments. Verify the sending service if you expected activity.")
        #expect(source.health?.lastEventDate != nil)
        #expect(source.health?.expectedEventDate != nil)
    }

    @Test @MainActor func notificationSourceRoutingDistinguishesSuccessMissingAndTransientFailure() async throws {
        let source = try JSONDecoder().decode(CustomPaymentSource.self, from: Data(#"""
        {
          "id": "source-health",
          "name": "SERP Store",
          "status": "active",
          "connectionState": "active",
          "webhookUrl": "https://example.test/private",
          "createdAt": "2026-08-11 00:00:00",
          "updatedAt": "2026-08-12 00:00:00"
        }
        """#.utf8))
        let detail = CustomSourceDetail(source: source, sample: nil, mapping: nil)
        let found = ConnectStore(customSourceDetailLoader: { _ in detail })
        let missing = ConnectStore(customSourceDetailLoader: { _ in throw APIError.notFound })
        let failed = ConnectStore(customSourceDetailLoader: { _ in
            throw URLError(.notConnectedToInternet)
        })

        #expect(await found.resolveCustomSourceRoute(id: source.id) == .found(source.id))
        #expect(found.customSources.map(\.id) == [source.id])
        #expect(await missing.resolveCustomSourceRoute(id: source.id) == .missing)
        #expect(await failed.resolveCustomSourceRoute(id: source.id) == .failed)
    }

    @Test func requestedSourceNeverUsesTheNewSourceForm() {
        #expect(CustomSourceSheetMode.showsNewSourceForm(sourceID: nil))
        #expect(!CustomSourceSheetMode.showsNewSourceForm(sourceID: "missing-source"))
    }
}
