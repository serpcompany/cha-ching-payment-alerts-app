# Cha-Ching Context

## Product

Cha-Ching is an iPhone app for indie founders and small software businesses. A user links the payment accounts they already own and receives a recognizable notification when a supported provider verifies a new sale.

The live MVP proves secure identity, plan access, provider-account linking, Stripe sale ingestion, real sales history, and APNs delivery. PayPal sale ingestion is not part of the first alert path.

## Domain vocabulary

- **User**: a person who signs in to Cha-Ching with Apple.
- **Provider**: an external payment system supported by Cha-Ching. The MVP providers are Stripe and PayPal.
- **Provider account**: the user's account at a provider. It is linked through provider-hosted authorization, never by pasting credentials into the app.
- **Connection**: Cha-Ching's revocable, least-privilege authorization to identify and read events for one provider account.
- **Entitlement**: server-owned permission enabling a feature for a user. UI presentation never grants access.
- **Sale**: a normalized, provider-verified payment event persisted without customer name or email.
- **Ping**: a user-visible APNs notification produced from a verified sale.

## Product invariants

- The iOS app never receives or persists provider access tokens.
- Provider consent happens on provider-controlled pages.
- One external provider account belongs to at most one Cha-Ching user.
- A connection requires an enabled entitlement both when authorization begins and when it completes.
- Sample data must not appear as production revenue.
- A provider may be entitled but unavailable when its production credentials are not configured.
- A provider connection does not imply that provider's sale-webhook path is supported.
- Stripe authorization must never include a write permission; the MVP reads only event and charge data.
- Production Stripe connections must pass a live-mode API probe before their account ID is stored; sandbox installs are rejected.
- Webhook retries must not create duplicate sales or duplicate completed notification deliveries.

## MVP success

A signed-in user can view entitlements and live provider availability, connect or disconnect one Stripe account and one PayPal account when configured, relaunch without losing their session, and see D1-backed connection state. A connected Stripe user receives one persisted sale and one notification attempt for each verified successful charge.
