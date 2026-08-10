# Sale Ingestion and Pings

## User outcome

A user with a connected Stripe account sees verified successful charges in Cha-Ching and receives an APNs notification on registered devices. The first alert path supports Stripe; PayPal sale webhooks remain future work.

## Stripe ingestion

- `POST /v1/webhooks/stripe` verifies Stripe's HMAC signature against the raw body with a five-minute timestamp tolerance.
- Connected-account `charge.succeeded` events are matched by Stripe account ID.
- Events for unknown accounts are recorded for deduplication and ignored as sales.
- A sale stores provider IDs, amount in minor units, currency, a generic product label, optional billing country, subscription indicator, and event time.
- Customer names, email addresses, descriptions, and full webhook payloads are not persisted.
- Unique provider event and payment IDs make retries idempotent.

## History and device registration

- `GET /v1/sales` returns at most the signed-in user's 100 newest verified sales.
- The iOS History tab reads this API; sample revenue and the local test-ping action have been removed.
- iOS asks for notification permission after a provider is connected, registers its APNs token through `POST /v1/devices`, refreshes it on launch, and removes the device on sign-out.
- Device tokens are never returned by a read API.

## Delivery

- A D1-backed sale ID is sent to the `cha-ching-notifications` Cloudflare Queue.
- The consumer creates at most one delivery per sale/device pair.
- Transient APNs failures retry; exhausted messages go to `cha-ching-notifications-dlq`.
- Invalid APNs tokens are disabled. A stale in-progress claim can be reclaimed after five minutes.
- Notification taps and foreground delivery trigger a fresh sales-history fetch.

## Data retention

Verified sale metadata and delivery records remain associated with the Cha-Ching account until account data is deleted. Disconnecting Stripe removes the authorization and encrypted tokens but does not erase existing history. A verified account-data deletion request removes the user's history and registered devices; minimal unmatched provider-event records may remain for webhook security and deduplication.

## Acceptance criteria

- A valid signed Stripe event for a connected account creates exactly one sale and schedules notification delivery; at-least-once Queue messages cannot create a second completed sale/device delivery.
- Replaying the event does not create another sale or completed delivery.
- Invalid, stale, oversized, malformed, or unsigned webhook requests cannot write a sale.
- A signed-in user can only list their own sales and manage their own device registration.
- A registered production device receives an amount/provider notification for a verified Stripe charge.
- Removing notification permission or signing out cannot expose another user's sales.

## Live verification status

The Worker, D1 schema, Queue consumer, API, and iOS client are implemented. Local runtime verification covers a signed Stripe event through D1 and Queue consumption. Production acceptance still requires Stripe platform credentials, webhook registration, a connected test account, and a successful push to a signed device.
