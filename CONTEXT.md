# Cha-Ching Context

## Product

Cha-Ching is an iPhone app for indie founders and small software businesses. A user links the payment accounts they already own and receives a recognizable payment notification when a supported source reports a successful payment.

The live MVP proves secure identity, entitlement enforcement, payment-source linking, Stripe payment ingestion, a real Payments feed, and APNs delivery. PayPal payment ingestion is not part of the first notification path.

## Domain vocabulary

- **User**: a person who signs in to Cha-Ching with Apple.
- **Provider**: an external payment system supported by Cha-Ching. The MVP providers are Stripe and PayPal.
- **Payment source**: any connected origin that can report payment data to Cha-Ching. A provider account is one kind of payment source; a custom webhook is another.
- **Custom webhook**: a user-named payment source with a durable private URL. During setup it captures one encrypted sample so the user can map fields; after activation it creates normalized sales.
- **Observed field**: a scalar path/value present in the current custom-webhook setup sample. It is not a claim about every field the sender could theoretically provide.
- **Field catalog**: a future sender-declared list of available fields. It is not implemented in the MVP.
- **Field mapping**: the user's ordered, saved choices for locating Payment ID, Amount, Currency, and notification display fields in a custom webhook payload.
- **Provider account**: the user's account at a provider. It is linked through provider-hosted authorization, never by pasting credentials into the app.
- **Connection**: Cha-Ching's revocable, least-privilege authorization to identify and read events for one provider account.
- **Entitlement**: server-owned permission enabling a feature for a user. UI presentation never grants access.
- **Payment**: the normalized successful-payment record shown on the Dashboard. Provider webhooks can verify a payment; custom-webhook payments are sender-reported.
- **Payment notification**: the user-visible iPhone notification produced from a payment. “Ping” is not product language.

## Product invariants

- The iOS app never receives or persists provider access tokens.
- Provider consent happens on provider-controlled pages.
- One external provider account belongs to at most one Cha-Ching user.
- A connection requires an enabled entitlement both when authorization begins and when it completes.
- Sample data must not appear as production revenue.
- A custom webhook URL remains stable across app and backend releases. Only the source owner's explicit regeneration invalidates it.
- A paused payment source retains its URL, mapping, and history while ignoring new events.
- Custom webhook samples are encrypted at rest and removed after activation.
- Custom webhook sales are reported by whoever possesses the private URL; Cha-Ching does not represent them as provider-verified.
- Custom notification previews and APNs bodies use the fixed title `Cha-ching!` and one ordered `{label}: {value}` line per enabled field. Different semantic fields are never combined into generated prose.
- Payment notifications use the bundled cash-register sound by default. Foreground presentation still requests banner, sound, and badge behavior from iOS.
- Connected Stripe and PayPal accounts can be paused without disconnecting; paused connections retain authorization and history while ignoring new payment events.
- A provider may be entitled but unavailable when its production credentials are not configured.
- A provider connection does not imply that provider's sale-webhook path is supported.
- Stripe authorization must never include a write permission; the MVP reads only event and charge data.
- Production Stripe connections must pass a live-mode API probe before their account ID is stored; sandbox installs are rejected.
- Webhook retries must not create duplicate sales or duplicate completed notification deliveries.

## MVP success

A signed-in user can view live provider availability, connect or disconnect one Stripe account and one PayPal account when configured, pause or resume payment intake, and see D1-backed state after relaunch. Entitlements remain a server-side access-control mechanism and are not presented as a “plan” in Settings. A connected active Stripe user receives one persisted payment and one payment-notification attempt for each verified successful charge. An active custom source can create sender-reported payments through its mapped private webhook.
