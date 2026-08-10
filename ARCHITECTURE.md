# Architecture

## Boundaries

- `Cha-Ching/` is the iOS presentation and native-auth client. It never stores provider credentials.
- `backend/src/index.ts` is the Worker HTTP boundary.
- Better Auth owns `user`, `session`, `account`, `verification`, and `rate_limit` in D1.
- Cha-Ching owns `entitlements`, `provider_connections`, `oauth_states`, `provider_events`, `sales`, `device_tokens`, and `notification_deliveries`.
- Stripe and PayPal OAuth modules are the only code allowed to exchange provider authorization codes.

## Request flow

1. iOS obtains an Apple ID token with a nonce and posts it to Better Auth.
2. Better Auth returns a bearer session; iOS stores it in Keychain.
3. iOS requests a provider authorization URL with that bearer session.
4. The Worker checks the D1 entitlement and persists only a hash of a ten-minute OAuth state.
5. The provider returns to the Worker. The Worker consumes the one-time state, rechecks entitlement, exchanges the code, encrypts tokens, and upserts the connection.
6. The Worker redirects to `chaching://oauth-callback`; iOS refreshes connection state from D1.

## Stripe sale-notification flow

1. Stripe sends a connected-account event to `/v1/webhooks/stripe`.
2. The Worker verifies the signature against the unmodified request body and rejects stale signatures.
3. A successful charge is matched to a connected Stripe account, normalized without customer name or email, and inserted idempotently into D1.
4. The Worker publishes the sale ID to `cha-ching-notifications` and records that it was queued.
5. The queue consumer claims one delivery per active device, signs an APNs provider token, and sends to Apple's development or production endpoint based on the registered token.
6. Completed deliveries are not repeated; transient failures retry and eventually move to `cha-ching-notifications-dlq`.
7. iOS refreshes `/v1/sales` when it receives or opens a notification.

## Security invariants

- API and provider secrets are Worker secrets, never Wrangler vars or iOS resources.
- Provider tokens use versioned AES-256-GCM ciphertext with a fresh 96-bit IV.
- OAuth state is random, short-lived, single-use, and stored only as SHA-256.
- Entitlements are enforced by the Worker; UI state is informational only.
- Provider connection rows are user-scoped, and one external account cannot be linked to multiple users.
- Apple email is recovered only from an already-linked local Better Auth account when Apple omits it on later sign-ins.
- Stripe webhook signatures are checked before JSON parsing or D1 writes.
- Provider event IDs, payment IDs, and notification deliveries are unique so retries are idempotent.
- APNs device tokens are user-scoped, revocable at sign-out, and invalidated after Apple rejects them.
