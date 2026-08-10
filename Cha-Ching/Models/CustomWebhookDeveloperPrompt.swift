import Foundation

enum CustomWebhookDeveloperPrompt {
    static func make(sourceName: String, webhookURL: URL) -> String {
        """
        Please integrate \(sourceName) with Cha-Ching, an iPhone payment-notification app.

        OVERVIEW
        Your job is to send successful-payment events from the existing store/payment system to Cha-Ching. Make changes only in the sender system you own; do not modify the Cha-Ching app or backend.

        PRIVATE WEBHOOK URL
        \(webhookURL.absoluteString)

        SECURITY
        - Treat this URL like a password. Anyone who has it can submit payments to this Cha-Ching source.
        - Store it in a server-side secret or environment variable. Never put it in browser/mobile code, source control, screenshots, public logs, or support tickets.
        - Send requests from a trusted backend only.
        - No additional API key, signature header, or Cha-Ching account login is required. The private URL is the credential.
        - If the URL is exposed, tell the Cha-Ching owner to regenerate it immediately.

        REQUEST REQUIREMENTS
        - Method: HTTP POST
        - Header: Content-Type: application/json
        - Maximum body size: 64 KiB
        - Trigger only for a completed/successful payment, not carts, authorizations, failures, refunds, or unrelated events.
        - Include a stable, unique Payment ID. Send IDs as JSON strings, especially long numeric IDs, so every character remains exact.
        - Include Amount and a three-letter ISO currency code such as USD or JPY.
        - Recommended optional fields: payment time, product, plan, and sale type.
        - Keep field names and nesting stable after setup.
        - Avoid customer names, emails, addresses, card data, or other personal data Cha-Ching does not need.

        EXAMPLE JSON
        {
          "payment": {
            "id": "pay_example_001",
            "amount": "27.00",
            "currency": "USD",
            "occurred_at": "2026-08-11T00:00:00Z",
            "product": "Example product",
            "plan": "Example plan",
            "sale_type": "one_time"
          }
        }

        SETUP AND TESTING
        1. Add the private URL to the sender's outgoing webhook configuration for successful payments.
        2. Send one representative test JSON event. During setup this becomes an encrypted field-mapping sample only; it does not create revenue or notify the phone.
        3. Tell the Cha-Ching owner the sample is ready. They will tap Check connection, map Payment ID/Amount/Currency and any optional fields, preview the notification, and activate the source.
        4. After the owner confirms activation, coordinate one clearly identifiable active test payment. It should create one Cha-Ching history item and one phone notification.
        5. Send the exact same active payload again with the same Payment ID. It must not create a second history item or notification.
        6. Retry network errors and non-2xx responses with the same Payment ID. Never generate a new ID for a retry.

        EXPECTED RESPONSES
        - Setup sample: HTTP 202 with received=true and sampleCaptured=true.
        - First active delivery: HTTP 202 with received=true and duplicate=false.
        - Exact active retry: HTTP 202 with received=true and duplicate=true.
        - Paused source: HTTP 202 with ignored=paused. Do not treat that as a sender failure.
        - Treat any other non-2xx response as unsuccessful and retain enough server-side diagnostics to retry safely without logging the private URL.

        COMPLETION CHECKLIST
        - Confirm the successful-payment trigger and the server-side location where the URL is stored.
        - Confirm the test request reached Cha-Ching with HTTP status and response body.
        - Confirm the field names supplied for Payment ID, Amount, Currency, Time, Product, Plan, and Sale type.
        - Confirm retry behavior preserves the original Payment ID.
        - Ask the Cha-Ching owner to confirm exactly one active test item and notification after the duplicate test.
        - Report the result without printing the private URL or unnecessary customer data.
        """
    }
}
