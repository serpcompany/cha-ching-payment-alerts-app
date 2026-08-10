# Custom Webhook Payment Sources

## User outcome

A signed-in user can connect any store or payment system that can send JSON to a webhook, without Cha-Ching needing provider-specific code.

## Setup experience

1. Tap **Connect another payment source** and give it a recognizable name.
2. Copy the private webhook URL into the sending system and choose its successful-payment event.
3. Send one test event, then tap **Check connection** in Cha-Ching.
4. Match the discovered fields to Payment ID, Amount, Currency, and optional Time, Product, Plan, and Sale type.
5. Preview the notification and activate the source.

The sender owns the payload shape. Cha-Ching discovers every scalar value in a valid payload up to 64 KiB and saves the user's mapping. A sample received during setup is never counted as revenue and never sends a notification.

## URL lifecycle

The webhook URL is random and stored with the payment source in D1. App builds, Worker deployments, and ordinary code changes do not change it. **Regenerate URL** is the only operation that replaces it, and the UI warns that the previous URL will stop working immediately.

The URL is itself the secret, following the familiar incoming-webhook setup model. It must be treated like a password and pasted only into the sending system's private webhook configuration.

## Active and paused behavior

- **Active**: valid mapped events become sales and queue notifications.
- **Paused**: new events are acknowledged and ignored; URL, mapping, and history remain.
- Retrying an active event with the same mapped Payment ID never creates a second sale. Once Queue acceptance is recorded it does not enqueue again; crash recovery may enqueue a duplicate message, which resolves to the same sale/device delivery and stable APNs id. Cha-Ching hashes the complete source-scoped ID; long IDs are never truncated before deduplication.
- A stale notification Queue claim is reclaimed after five minutes when the sender retries the same mapped Payment ID; Queue acceptance is recorded only after the send succeeds.
- Numeric Payment IDs are supported only while they are JavaScript-safe integers. Send large IDs as JSON strings, or map a string field, so every digit remains exact for deduplication.

## Privacy and limits

- Payload limit: 64 KiB.
- Setup samples use the existing versioned AES-256-GCM Worker encryption key.
- The sample is deleted when the source is activated.
- Active raw payloads are never persisted.
- Only normalized sale fields enter history.
- Custom sales are sender-reported. The private URL authenticates the sender but does not provide independent payment-provider verification.
- Malformed JSON is reported as a setup error; active payloads missing a required mapped value are rejected.

## Acceptance criteria

- An authenticated owner can create and list named sources; another user cannot view, change, pause, resume, or regenerate them.
- A private URL remains identical until its owner explicitly regenerates it.
- Setup samples expose selectable scalar paths and values without affecting history or notifications.
- A valid mapping produces a preview before activation.
- Changing any mapping or amount-format choice invalidates the preview; activation requires the exact mapping that was previewed.
- Active retries are idempotent by the source-scoped mapped Payment ID.
- Pausing and resuming does not replace the URL or erase history.
- Oversized, malformed, or unmappable payloads do not create sales.

## Production status

Migrations `0005` through `0008` and Worker version `dfb64838-e4f8-44bd-a24f-b928d0c8b2d8` were deployed on 2026-08-11 JST. Existing production users, connections, Stripe events, sales, and notification deliveries were preserved. TestFlight build `4` (`4722b680-6592-4e88-acc0-2e3965c52398`) is valid and in internal beta testing with this UI. Final acceptance requires creating a source on a signed iPhone, receiving a real sender sample, activating its mapping, and observing one live history item and notification.
