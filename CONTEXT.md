# Sales Ping Context

## Product

Sales Ping is an iPhone app for indie founders and small software businesses. A user links the payment accounts they already own and, in later milestones, receives a recognizable notification when a new sale is verified.

The first live MVP proves secure identity, plan access, and provider-account linking. It does not claim to ingest revenue yet.

## Domain vocabulary

- **User**: a person who signs in to Sales Ping with Apple.
- **Provider**: an external payment system supported by Sales Ping. The MVP providers are Stripe and PayPal.
- **Provider account**: the user's account at a provider. It is linked through provider-hosted authorization, never by pasting credentials into the app.
- **Connection**: Sales Ping's revocable authorization to identify and later read events for one provider account.
- **Entitlement**: server-owned permission enabling a feature for a user. UI presentation never grants access.
- **Sale**: a normalized, provider-verified payment event. No production sale exists until ingestion is implemented.
- **Ping**: a user-visible notification produced from a verified sale. The current test ping is local demonstration behavior, not a real sale.

## Product invariants

- The iOS app never receives or persists provider access tokens.
- Provider consent happens on provider-controlled pages.
- One external provider account belongs to at most one Sales Ping user.
- A connection requires an enabled entitlement both when authorization begins and when it completes.
- Sample data must not appear as production revenue.
- Shipping account connection does not imply that webhooks, sale ingestion, or notifications are live.

## MVP success

A signed-in user can view their entitlements, connect or disconnect one Stripe account and one PayPal account, relaunch the app without losing their Sales Ping session, and see connection state backed by production D1.
