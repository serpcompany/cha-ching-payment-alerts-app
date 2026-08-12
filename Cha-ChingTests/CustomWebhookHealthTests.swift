import Foundation
import Testing
@testable import Cha_Ching

struct CustomWebhookHealthTests {
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
        #expect(source.health?.statusTitle == "Needs checking")
        #expect(source.health?.lastEventDate != nil)
    }
}
