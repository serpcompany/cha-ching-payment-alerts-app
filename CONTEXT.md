# Cha-Ching Context

## Product

Cha-Ching is an iPhone app for indie founders and small software businesses. A user links the payment accounts they already own and receives a recognizable payment notification when a supported source reports a successful payment.

The live MVP proves secure identity, entitlement enforcement, payment-source linking, Stripe payment ingestion, a real Payments feed, and APNs delivery. PayPal payment ingestion is not part of the first notification path.

## Domain vocabulary

- **User**: a person who signs in to Cha-Ching with Apple.
- **Provider**: an external payment system supported by Cha-Ching. The MVP providers are Stripe and PayPal.
- **Payment source**: any connected origin that can report payment data to Cha-Ching. A provider account is one kind of payment source; a custom webhook is another.
- **Custom webhook**: a user-named payment source with a durable private URL. During setup it waits for the sender's first real event and captures that event as one encrypted setup sample so the user can map fields; after activation it creates normalized payments.
- **Observed field**: a scalar path/value present in the current custom-webhook setup sample. It is not a claim about every field the sender could theoretically provide.
- **Field catalog**: a future sender-declared list of available fields. It is not implemented in the MVP.
- **Field mapping**: the user's ordered, saved choices for locating Payment ID, Amount, Currency, and notification display fields in a custom webhook payload.
- **Provider account**: the user's account at a provider. It is linked through provider-hosted authorization, never by pasting credentials into the app.
- **Connection**: Cha-Ching's revocable, least-privilege authorization to identify and read events for one provider account.
- **Subscription**: a user's commercial access relationship with Cha-Ching, as reported by a billing provider.
- **Entitlement**: Cha-Ching's billing-provider-independent grant of permission to use a product capability. UI presentation and client state never grant it.
- **Payment**: the normalized successful-payment record shown on the Dashboard. Provider webhooks can verify a payment; custom-webhook payments are sender-reported.
- **Payment notification**: the user-visible iPhone notification produced from a payment. “Ping” is not product language.

## Product invariants

- The iOS app never receives or persists provider access tokens.
- Provider consent happens on provider-controlled pages.
- One external provider account belongs to at most one Cha-Ching user.
- A connection requires an enabled entitlement both when authorization begins and when it completes.
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

A signed-in user can view live provider availability, connect or disconnect one Stripe account and one PayPal account when configured, pause or resume payment intake, clear Cha-Ching's stored Stripe payment history without disconnecting, and see D1-backed state after relaunch. Entitlements remain a server-side access-control mechanism and are not presented as a “plan” in Settings. A connected active Stripe user receives one persisted payment and one payment-notification attempt for each verified successful charge. An active custom source can create sender-reported payments through its mapped private webhook.
