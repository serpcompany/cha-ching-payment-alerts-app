# Architecture

## Boundaries

- `Sales Ping/` is the iOS presentation and native-auth client. It never stores provider credentials.
- `backend/src/index.ts` is the Worker HTTP boundary.
- Better Auth owns `user`, `session`, `account`, `verification`, and `rate_limit` in D1.
- Sales Ping owns `entitlements`, `provider_connections`, and `oauth_states`.
- Stripe and PayPal OAuth modules are the only code allowed to exchange provider authorization codes.

## Request flow

1. iOS obtains an Apple ID token with a nonce and posts it to Better Auth.
2. Better Auth returns a bearer session; iOS stores it in Keychain.
3. iOS requests a provider authorization URL with that bearer session.
4. The Worker checks the D1 entitlement and persists only a hash of a ten-minute OAuth state.
5. The provider returns to the Worker. The Worker consumes the one-time state, rechecks entitlement, exchanges the code, encrypts tokens, and upserts the connection.
6. The Worker redirects to `salesping://oauth-callback`; iOS refreshes connection state from D1.

## Security invariants

- API and provider secrets are Worker secrets, never Wrangler vars or iOS resources.
- Provider tokens use versioned AES-256-GCM ciphertext with a fresh 96-bit IV.
- OAuth state is random, short-lived, single-use, and stored only as SHA-256.
- Entitlements are enforced by the Worker; UI state is informational only.
- Provider connection rows are user-scoped, and one external account cannot be linked to multiple users.
- Apple email is recovered only from an already-linked local Better Auth account when Apple omits it on later sign-ins.
