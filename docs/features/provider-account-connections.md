# Provider Account Connections

## User outcome

An entitled user can connect or disconnect their own Stripe and PayPal accounts using provider-hosted consent pages.

## Stripe

- Cha-Ching is a backend-only public Stripe App owned by DS Apps (`acct_1T3IiJE8IBJK847r`). The accepted live test installation is the separate SERP! payment account (`acct_1Rba2Z06JrOmKRCm`); DS Apps is never treated as the user's payment account.
- The manifest grants only `event_read` and `charge_read`. It does not request any write permission and cannot create, refund, or change a payment.
- The account selected on Stripe's install page is the signed-in user's existing Stripe account. It becomes an installed user account, not Cha-Ching's developer account.
- The Worker adds a ten-minute state value to the Stripe App install URL, verifies Stripe's signed callback, and stores only the returned account ID.
- In production, the callback also performs a read-only live-mode Charge probe through Stripe. A sandbox account is rejected instead of being reported as connected.
- Before Marketplace publication, the install setting uses Stripe's external-test link at `https://dashboard.stripe.com/apps/install/link/...`. The Worker accepts only that exact test path or a published `marketplace.stripe.com` app link.
- No Stripe OAuth access or refresh token is issued or stored for this platform-key Stripe App flow.
- Stripe sends permitted installed-account events to the configured webhook. The Worker does not need a Stripe API request to ingest a `charge.succeeded` payload.
- Removing the connection in Cha-Ching immediately removes its local account mapping. Uninstalling Cha-Ching in Stripe's Installed Apps settings revokes the Stripe-side installation and emits `account.application.deauthorized`.

## PayPal

- Uses Log in with PayPal and OpenID Connect.
- Uses PayPal's current `/signin/authorize` endpoint and Identity API token/user-info endpoints.
- Requests only identity/profile scopes needed to identify the account.
- Sandbox is suitable for MVP verification; live mode requires PayPal approval.
- Disconnect removes Cha-Ching's locally stored encrypted authorization.

Reference: [PayPal Log in integration](https://developer.paypal.com/log-in/build).

## Shared security behavior

- Authorization state is 256-bit random, expires after ten minutes, is stored only as SHA-256, and is consumed once.
- The entitlement is checked before issuing an authorization URL and after consuming the callback.
- Provider access and refresh tokens, when a provider issues them, are AES-256-GCM encrypted with a per-write random IV. Stripe App installs do not store tokens.
- Provider tokens never cross the iOS API boundary.
- A provider/account ID pair is unique across Cha-Ching users.
- `/v1/me` reports server-side provider availability separately from entitlement state, so the app disables connection actions until required credentials exist.

## Acceptance criteria

- Connected status and provider-owned account label survive app relaunch.
- Cancelled, expired, replayed, malformed, or wrong-provider callbacks do not create a connection.
- A disabled entitlement returns 403 and cannot be bypassed with a callback.
- Disconnect is idempotent and removes the visible connection.
- A configured provider is actionable; an unconfigured provider is visibly unavailable and cannot create OAuth state.
- Stripe's permission screen lists only event and charge read access and contains no create, update, refund, or other write capability.
- A signed production callback for a Stripe sandbox returns an error and cannot replace a live connection.
