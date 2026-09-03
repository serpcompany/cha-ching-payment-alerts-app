# Payment Ingestion and Notifications

## User outcome

A user with a connected Stripe account or active custom webhook source sees successful payments in Cha-Ching and receives an APNs notification on registered devices. PayPal sale webhooks remain future work.

Custom webhook ingestion is documented separately in `custom-webhook-payment-sources.md`. It trusts possession of the source's private URL rather than claiming provider verification, never stores the active raw payload, and retains only normalized sale data plus the enabled notification label/value pairs.

Custom notifications have a fixed `Cha-ching!` title. Their body is deterministic: every enabled structured field appears on its own ordered `{Display label}: {Formatted value}` line. Product, Purchase Type, Sale Event, and every other semantic field remain separate rather than being combined into prose. Missing optional values are omitted, and the preview endpoint is tested against the exact APNs body.

## Stripe ingestion

- The Stripe App manifest grants `event_read` and `charge_read`; no write permission is requested.
- `POST /v1/webhooks/stripe` verifies Stripe's HMAC signature against the raw body with a five-minute timestamp tolerance.
- Connected-account `charge.succeeded` events are matched by Stripe account ID.
- Events for unknown accounts are recorded for deduplication and ignored as sales.
- Provider-event audit rows distinguish recoverable `received` events from final `ignored` and `processed` events. Paused or unknown-account events remain ignored if replayed later.
- A sale stores provider IDs, amount in minor units, currency, a generic product label, optional billing country, subscription indicator, and event time.
- Customer names, email addresses, descriptions, and full webhook payloads are not persisted.
- Unique provider event and payment IDs make retries idempotent.
- If sale persistence, Queue acceptance, or a pre-send Worker execution fails transiently, replaying the exact signed active event resumes processing. A stale pre-send claim is reclaimable after five minutes.

## History and device registration

- `GET /v1/sales` returns at most the signed-in user's 100 newest sales. Stripe entries are provider-verified; custom entries are sender-reported.
- The Payments screen reads this API. Each custom sale includes its immutable ordered snapshot of enabled notification label/value fields for drill-down; sample revenue is not part of production behavior.
- iOS asks for notification permission after a provider is connected, registers its APNs token through `POST /v1/devices`, refreshes it on launch only while the user's Payment notifications preference is on, and removes the device on sign-out or when that preference is turned off.
- The UI reports payment notifications as on only after both notification permission and backend device registration succeed. Simulator permission alone is not presented as a working push channel; production push acceptance uses a signed iPhone build.
- Device tokens are never returned by a read API.

## Delivery

- A D1-backed sale ID is sent to the `cha-ching-notifications` Cloudflare Queue.
- Queue acceptance is recorded separately from its reclaimable pre-send claim. A Worker that stops after claiming cannot permanently suppress the notification.
- The consumer creates at most one delivery per sale/device pair.
- Duplicate Queue messages reuse the persisted delivery row ID as the APNs id, so recovery does not create a second user-visible delivery.
- Transient APNs failures retry; exhausted messages go to `cha-ching-notifications-dlq`.
- Invalid APNs tokens are disabled. A stale in-progress claim can be reclaimed after five minutes.
- Notification taps and foreground delivery trigger a fresh sales-history fetch. A real payment tap selects Payments and opens the matching D1-backed payment; a setup test tap opens its standalone preview because no sale exists. The response returns control to UIKit on the main thread so cold-launch state restoration cannot crash the app.
- Foreground delivery requests Apple's real banner, list, sound, and badge presentation. Apple limits the abbreviated system preview to a few lines; the in-app payment detail contains every configured custom field saved for that payment.
- A sample can also be queued as a delayed lock-screen test. The authenticated request validates the current preview, confirms a registered device, and places the exact body on Cloudflare Queue without creating a payment; the Queue consumer sends it after the delay.
- Live and sample-based test notifications use the bundled, level-checked cash-register sound by default. System mute, Focus, permission, and foreground-presentation rules remain controlled by iOS.
- Custom-source health warnings use the existing notification Queue and active-device boundary, carry `connectionHealth: true` plus the affected source ID, and use the default system sound. Pressing one selects Settings, pushes Payment sources, and opens that source rather than pretending a missing sale exists.

## Data retention

Sale metadata and delivery records remain associated with the Cha-Ching account until the user explicitly clears that source's history or account data is deleted. Pausing Stripe preserves its connection and history while ignoring new charges. **Clear payment history** deletes only the signed-in user's normalized Stripe payments and cascades to their delivery records while preserving the connection and active/paused setting. Disconnecting Stripe removes Cha-Ching's local account mapping but does not erase existing history. Uninstalling Cha-Ching in Stripe revokes the Stripe-side installation. A verified account-data deletion request removes the user's history and registered devices; minimal provider-event audit records may remain for webhook security and deduplication so a cleared payment cannot be recreated by a replay.

## Acceptance criteria

- A valid signed Stripe event for a connected account creates exactly one sale and schedules notification delivery; at-least-once Queue messages cannot create a second completed sale/device delivery.
- Replaying the event does not create another sale or completed delivery.
- A transient D1 sale-insert, Queue-send, or abandoned pre-send claim remains recoverable on exact-event retry without duplicating the sale or user-visible delivery.
- An event first received while the connection is paused remains ignored after resume.
- Invalid, stale, oversized, malformed, or unsigned webhook requests cannot write a sale.
- Missing display-only custom-webhook fields do not reject an otherwise valid payment; those rows are omitted from that payment's notification while required normalization fields remain enforced.
- A signed-in user can only list their own sales and manage their own device registration.
- A registered production device receives an amount/provider notification for a verified Stripe charge.
- Removing notification permission or signing out cannot expose another user's sales.
- Turning Payment notifications off removes that phone's backend registration and prevents launch-time re-registration until the user turns it on again.
- Clearing Stripe payment history removes only that user's Stripe payments and delivery records, preserves the connection and paused setting, and leaves custom-source payments intact.
- Immediate foreground testing presents a genuine Apple notification and exposes every selected structured line after the user presses it. Delayed lock-screen testing does not depend on the app staying active after the server accepts the request, and opening that notification must safely cold-launch the detail presentation.
- A custom-source health warning is emitted at most once per uninterrupted warning state and routes to the affected source; a later healthy request resets eligibility for a future warning.

## Live verification status

The Worker, D1 schema, Queue consumer, API, and iOS client are implemented. Stripe App version 0.1.0 is approved under the DS Apps owner account, and its live connected-account event destination is active. On 2026-08-11 JST, diagnosis found that the first installation had linked a Stripe sandbox while the real payment occurred on the separate live SERP! account. Cha-Ching was then installed on the live account, and Stripe's actual `$27.00` successful Charge event was replayed through the signed production webhook. D1 persisted the real payment, Queue processed it, APNs accepted one production delivery on the first attempt, and the user confirmed that the notification appeared on the signed iPhone. Replaying the exact event left one payment and one delivery. Later that day, production evidence showed three `serp.store` custom-webhook attempts returning 422 because optional display fields were absent. Worker version `094b0852-7314-4479-94b7-0b69259e6aaa` fixed that contract and passed a production webhook → D1 → Queue → APNs smoke test with missing attribution fields. TestFlight build 15 contains production APNs signing, universal custom sources with always-visible activation, provider pause and Stripe-history-clear controls, retry/crash recovery, configurable all-fields notifications, a real per-device notification toggle, genuine Apple notification surfaces, crash-safe cold-launch tap-through details, delayed lock-screen testing, cash-register sound, badge clearing without synthetic unread counts, and a Payments-only Dashboard whose concurrent refresh callers cannot flash a false failure while the shared request succeeds. A production callback regression test rejects sandbox accounts before they can be stored as connected.
