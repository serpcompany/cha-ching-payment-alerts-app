# Cha-Ching Context

## Product

Cha-Ching is an iPhone app for indie founders and small software businesses. A user links the payment accounts they already own and receives a recognizable payment notification when a supported source reports a successful payment.

The live MVP proves secure identity, entitlement enforcement, payment-source linking, Stripe payment ingestion, a real Payments feed, and APNs delivery. PayPal payment ingestion is not part of the first notification path.

## Domain vocabulary

- **User**: a person who signs in to Cha-Ching with Apple.
- **Provider**: an external payment system supported by Cha-Ching. The MVP providers are Stripe and PayPal.
- **Payment source**: any connected origin that can report payment data to Cha-Ching. A provider account is one kind of payment source; a custom webhook is another.
- **Custom webhook**: a user-named payment source with a durable private URL. During setup it waits for the sender's first real event and captures that event as one encrypted setup sample so the user can map fields; after activation it creates normalized payments.
- **Observed field**: a scalar path Cha-Ching has encountered in a custom-webhook event. It is not a claim about every field the sender could theoretically provide.
- **Available field**: an observed field offered to the source owner for notification configuration. Availability does not imply that the field has a value in earlier payments.
- **Field catalog**: a future sender-declared list of fields, including fields Cha-Ching may not yet have observed. It is not implemented in the MVP.
- **Field mapping**: the user's ordered, saved choices for locating Payment ID, Amount, Currency, and notification display fields in a custom webhook payload.
- **Provider account**: the user's account at a provider. It is linked through provider-hosted authorization, never by pasting credentials into the app.
- **Connection**: Cha-Ching's revocable, least-privilege authorization to identify and read events for one provider account.
- **Entitlement**: server-owned permission enabling a feature for a user. UI presentation never grants access.
- **Subscription**: the commercial relationship Apple reports for Cha-Ching's annual product. It is translated into a provider-independent product entitlement before it can grant access.
- **Payment**: the normalized successful-payment record shown in Payments and counted by Home reports. Provider webhooks can verify a payment; custom-webhook payments are sender-reported.
- **Reporting timezone**: the user's saved IANA timezone that defines day, month, quarter, and year boundaries on Home. Payment timestamps remain UTC.
- **Payment notification**: the user-visible iPhone notification produced from a payment. “Ping” is not product language.

## Product invariants

- The iOS app never receives or persists provider access tokens.
- Provider consent happens on provider-controlled pages.
- One external provider account belongs to at most one Cha-Ching user.
- A connection requires an enabled entitlement both when authorization begins and when it completes.
- Full product access requires a current, backend-verified product entitlement. An active trial or paid period grants access through its recorded expiration; expiration, refund, or revocation turns access off.
- StoreKit and UI state never grant access. Purchase and restore submit Apple's signed transaction to the Worker, and D1 remains the authorization source of truth.
- Events received while product access is off are acknowledged and durably ignored. They are not backfilled after access returns.
- Sample data must not appear as production revenue.
- Production custom-webhook setup never preloads fabricated data. Its user-visible lifecycle is **Waiting for first event** → **Event received** → **Active**, driven by sender traffic and explicit activation.
- A custom webhook URL remains stable across app and backend releases. Only the source owner's explicit regeneration invalidates it.
- Pausing a payment source retains its URL, mapping, and existing payments while ignoring new events. A separate, explicitly confirmed clear-history action may remove that source's normalized payments without changing its connection or paused setting.
- Custom webhook samples are encrypted at rest and removed after activation.
- Custom-webhook payments are reported by whoever possesses the private URL; Cha-Ching does not represent them as provider-verified.
- Custom notification previews and APNs bodies use the fixed title `Cha-ching!` and one ordered `{label}: {value}` line per enabled field. Different semantic fields are never combined into generated prose.
- Payment notifications use the bundled cash-register sound by default. Foreground delivery uses Apple's real system banner. Apple's compact banner and lock-screen preview show only a few body lines; pressing a notification safely opens Cha-Ching's full scrollable detail presentation with every selected structured field, including when the app was not running.
- Payment notifications do not invent an unread-count badge. Cha-Ching clears any existing app-icon badge when the app opens, becomes active, or a notification is pressed.
- Payment notifications are an explicit per-device user preference. Off removes the backend device registration and blocks automatic re-registration; on registers again when system permission allows it.
- A lock-screen sample test is delayed by the server-side Queue after acceptance so the user can lock the phone without suspending the send.
- Connected Stripe and PayPal accounts can be paused without disconnecting; paused connections retain authorization and existing payments while ignoring new payment events. Clearing Stripe payment history is a distinct user action that affects only Cha-Ching's stored Stripe payments, not Stripe itself.
- A provider may be entitled but unavailable when its production credentials are not configured.
- A provider connection does not imply that provider's payment-webhook path is supported.
- Stripe authorization must never include a write permission; the MVP reads only event and charge data.
- Production Stripe connections must pass a live-mode API probe before their account ID is stored; sandbox installs are rejected.
- Webhook retries must not create duplicate payments or duplicate completed notification deliveries.

## MVP success

A signed-in user with Full access can view live provider availability, connect or disconnect one Stripe account and one PayPal account when configured, pause or resume payment intake, clear Cha-Ching's stored Stripe payment history without disconnecting, and see D1-backed state after relaunch. A user without Full access sees Subscription required with purchase, restore, and management actions. The launch offer is one $14.99/year Apple auto-renewing subscription with a seven-day introductory trial. A connected active Stripe user receives one persisted payment and one payment-notification attempt for each verified successful charge. An active custom source can create sender-reported payments through its mapped private webhook.
