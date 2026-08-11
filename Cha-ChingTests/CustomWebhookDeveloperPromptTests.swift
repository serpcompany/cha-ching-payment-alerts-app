import Foundation
import Testing
@testable import Cha_Ching

struct CustomWebhookDeveloperPromptTests {
    @Test func includesTheSourceURLContractAndVerificationSteps() throws {
        let url = try #require(URL(string: "https://api.example.test/v1/webhooks/custom/private-token"))
        let prompt = CustomWebhookDeveloperPrompt.make(sourceName: "SERP Store", webhookURL: url)

        #expect(prompt.contains("Please integrate SERP Store with Cha-Ching"))
        #expect(prompt.contains(url.absoluteString))
        #expect(prompt.contains("Treat this URL like a password"))
        #expect(prompt.contains("Method: HTTP POST"))
        #expect(prompt.contains("Content-Type: application/json"))
        #expect(prompt.contains("Payment ID"))
        #expect(prompt.contains("Amount"))
        #expect(prompt.contains("Currency"))
        #expect(prompt.contains("checkout_country_ip"))
        #expect(prompt.contains("purchase_type"))
        #expect(prompt.contains("sale_event"))
        #expect(prompt.contains("dub_affiliate_id"))
        #expect(prompt.contains("utm_source"))
        #expect(prompt.contains("Every structured field is rendered on its own line"))
        #expect(prompt.contains("Purchase Type: Subscription"))
        #expect(prompt.contains("Sale Event: New sale"))
        #expect(prompt.contains("HTTP 202"))
        #expect(prompt.contains("duplicate=true"))
        #expect(prompt.contains("exactly one active test item and notification"))
    }
}
