# Provider Account Connections

## User outcome

An entitled user can connect or disconnect their own Stripe and PayPal accounts using provider-hosted consent pages.

## Stripe

- Uses Stripe Connect OAuth for Standard accounts.
- Requests `read_write` access so later sale ingestion can act for the connected account.
- Stores the Stripe account ID plus encrypted access/refresh tokens.
- Disconnect calls Stripe deauthorization before removing the local connection.

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
- Access and refresh tokens are AES-256-GCM encrypted with a per-write random IV.
- Provider tokens never cross the iOS API boundary.
- A provider/account ID pair is unique across Cha-Ching users.

## Acceptance criteria

- Connected status and provider-owned account label survive app relaunch.
- Cancelled, expired, replayed, malformed, or wrong-provider callbacks do not create a connection.
- A disabled entitlement returns 403 and cannot be bypassed with a callback.
- Disconnect is idempotent and removes the visible connection.
