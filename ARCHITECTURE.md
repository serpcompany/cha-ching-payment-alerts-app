# Architecture

## Boundaries

- `Cha-Ching/` is the iOS presentation and native-auth client. It never stores provider credentials.
- `backend/src/index.ts` is the Worker HTTP boundary.
- Better Auth owns `user`, `session`, `account`, `verification`, and `rate_limit` in D1.
- Cha-Ching owns `entitlements`, `provider_connections`, `oauth_states`, `provider_events`, `custom_payment_sources`, `sales`, `device_tokens`, and `notification_deliveries`.
- Stripe and PayPal OAuth modules are the only code allowed to exchange provider authorization codes.

## Request flow

1. iOS obtains an Apple ID token with a nonce and posts it to Better Auth.
2. Better Auth returns a bearer session; iOS stores it in Keychain.
3. iOS requests a provider authorization URL with that bearer session.
4. The Worker checks the D1 entitlement and persists only a hash of a ten-minute OAuth state.
5. The provider returns to the Worker. The Worker consumes the one-time state and rechecks entitlement. Stripe App installs are verified with the app signing secret; production installs must also pass a live-mode, read-only Charge probe before the account ID is stored. Providers that issue OAuth tokens are exchanged and encrypted.
6. The Worker redirects to `chaching://oauth-callback`; iOS refreshes connection state from D1.

## Stripe sale-notification flow

1. Stripe sends a connected-account event to `/v1/webhooks/stripe`.
2. The Worker verifies the signature against the unmodified request body and rejects stale signatures.
3. A successful charge is matched to a connected Stripe account. Its event audit is marked `received`, then the normalized sale is inserted idempotently without customer name or email.
4. The Worker takes a five-minute reclaimable notification claim, publishes the sale ID to `cha-ching-notifications`, records Queue acceptance, and marks the event `processed`. A failed sale insert, Queue send, or abandoned pre-send claim remains recoverable on Stripe's exact-event retry.
5. The queue consumer claims one delivery per active device, reuses that delivery row's stable ID as the APNs id, signs an APNs provider token, and sends to Apple's development or production endpoint based on the registered token.
6. Completed deliveries are not repeated; duplicate Queue messages resolve to the same sale/device row and APNs id. Transient failures retry and eventually move to `cha-ching-notifications-dlq`.
7. iOS refreshes `/v1/sales` when it receives or opens a notification.

A connected provider's `is_active` flag is checked before sale insertion. Pausing preserves authorization and history while new provider events receive a durable `ignored` disposition, so replaying one after resume cannot turn it into a sale.

## Custom webhook flow

1. An entitled, authenticated user names a payment source. The Worker generates a random private URL token, stores its hash for lookup, and stores an encrypted copy so the same URL can be shown again.
2. While the source is in setup, `POST /v1/webhooks/custom/:token` encrypts one JSON sample. Samples never create sales or notifications.
3. iOS checks the connection, displays every observed scalar field path and value in the bounded payload, and lets the user map Payment ID, Amount, Currency, and optional history fields. Observed means present in this sample; the MVP has no sender-declared catalog of every possible field.
4. A notification designer creates one initially enabled row for every observed field. The user can search and filter rows, show or hide each one, rename its display label, remap it to any observed path, and set its stable order.
5. The Worker validates the complete mapping against the sample and returns the exact normalized notification preview: fixed title `Cha-ching!` and one ordered `{label}: {value}` line per enabled field. Activation requires that exact previewed mapping and deletes the encrypted sample.
6. An active source normalizes incoming JSON with the saved mapping, hashes the complete source-scoped Payment ID, stores only the enabled notification label/value pairs with the sale, and queues one notification. Retries with the same full mapped Payment ID are ignored.
7. A paused source acknowledges and ignores new events while retaining its URL, mapping, and history.

## Security invariants

- API and provider secrets are Worker secrets, never Wrangler vars or iOS resources.
- Provider tokens use versioned AES-256-GCM ciphertext with a fresh 96-bit IV.
- OAuth state is random, short-lived, single-use, and stored only as SHA-256.
- Entitlements are enforced by the Worker; UI state is informational only.
- Provider connection rows are user-scoped, and one external account cannot be linked to multiple users.
- Apple email is recovered only from an already-linked local Better Auth account when Apple omits it on later sign-ins.
- Stripe webhook signatures are checked before JSON parsing or D1 writes.
- Stripe App install callbacks are signed, and the app manifest grants only `event_read` and `charge_read`.
- A sandbox Stripe account cannot be stored by a production callback, even though sandbox and live identifiers share the `acct_` format.
- Provider event IDs, payment IDs, and notification deliveries are unique so retries are idempotent.
- Custom webhook tokens have 256 bits of entropy. D1 uses their SHA-256 hashes for public request lookup; encrypted token copies are returned only through owner-authenticated APIs.
- Custom payloads are limited to 64 KiB. Setup samples are encrypted at rest, never logged, and removed on activation; active payloads are normalized without storing the original JSON. Only enabled notification labels and values are retained with a sale.
- A custom URL authenticates its sender but does not independently verify the truth of the reported sale.
- APNs device tokens are user-scoped, revocable at sign-out, and invalidated after Apple rejects them.
