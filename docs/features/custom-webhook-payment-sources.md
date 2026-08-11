# Custom Webhook Payment Sources

## User outcome

A signed-in user can connect any store or payment system that can send JSON to a webhook, without Cha-Ching needing provider-specific code.

## Setup experience

1. Tap **Connect another payment source** and give it a recognizable name.
2. Copy either the private webhook URL or **Copy instructions for developer**. The copied instructions include the URL, security rules, request contract, setup steps, test expectations, retry check, and completion checklist.
3. Send one test event, then tap **Check connection** in Cha-Ching.
4. Tap **Customize notifications** to move to a separate **Notification settings** screen. Payment matching and notification design live there; the connection screen does not contain a separate **Match the payment** section.
5. Confirm or adjust Payment ID, Amount, Currency, amount format, and optional payment mappings in the notification-settings experience.
6. Every observed scalar field appears once and starts on. The compact ordered list shows only the user-facing label, example value, and direct on/off switch. Tap a row to rename it, remap it, or move it; the technical source path appears only inside that detail screen.
7. Tap **Preview notification** to review the exact multiline body. **Test notification** sends that same sample immediately without creating a payment; while Cha-Ching is open, every selected line appears in a full scrollable sheet. **Test lock screen** asks the Worker to queue the exact sample for a short delay and then tells the user to lock the iPhone. **Activate payment source** remains in the preview.

The sender owns the payload shape. Cha-Ching discovers every scalar value actually present in a valid sample payload up to 64 KiB and saves the user's mapping and notification design. A sample received during setup is never counted as revenue and never sends a notification. Changing a field toggle, label, mapping, or order invalidates the old preview, so activation always uses the design currently visible on screen.

The selected UI is Variant A from the throwaway [notification-settings prototype](https://github.com/serpcompany/cha-ching/tree/prototype/notification-settings-variants/prototypes/notification-settings-prototype). The prototype branch records the design decision and is not merged into the product branch.

## Screen model and interaction rules

The MVP keeps payment-source connection and notification design as two distinct jobs:

1. **Connect tab** — shows one card per custom source with its name and current setup, active, or paused status.
2. **Payment-source setup** — creates the source, exposes the durable private URL and developer instructions, and checks for a sample. It does not contain payment-field pickers or notification rows.
3. **Notification settings** — opens from the dedicated **Customize notifications** next step after a sample is found. It owns both payment matching and notification design, shows the source as connected, provides preview and test actions, and contains an ordered list with every observed field exactly once.
4. **Field row** — shows only the display label, sample value, disclosure indicator, and a direct on/off switch. The section header shows the current included count, such as **15 of 17 on**.
5. **Edit detail** — tapping a row opens its focused editor. The user can show or hide the line, rename its display label, remap it to any observed payload field, inspect the example and technical path, move it earlier or later, and see that line's preview. The main list also supports drag reordering through **Edit**.
6. **Notification preview and device test** — Preview notification shows an iPhone-style preview containing the exact title, line order, labels, and sample values that will be sent. The adjacent Test notification action sends that design through APNs using the cash-register sound and reports whether a registered device accepted it. **Activate payment source** remains an explicit confirmation of the previewed design.
7. **Active-source management** — reopening an activated source currently provides pause/resume, URL copy, developer-prompt copy, and explicit URL regeneration. Editing an already activated notification design is not part of the current MVP; configuration happens before activation.

The notification screen deliberately avoids repeating technical source paths or a full preview beneath every row. Technical details are disclosed only when editing a field, and the complete notification appears in one dedicated preview. Build 8 does not include search or filtering; the compact ordered list is the current all-fields navigation model.

## Field vocabulary and notification contract

- **Observed field** means a scalar path/value present in the setup sample. It does not mean every theoretical field the sender could provide.
- **Available field** is reserved for a future sender-declared field catalog. The MVP does not yet accept a catalog, so the app must never claim the sample represents every possible field.
- The current honest fallback is to send one representative setup event containing every field the user may want to configure. If the developer later adds a field, the source needs a new setup/mapping flow before that field can be selected.
- The push title is always **Cha-ching!**.
- Every enabled structured field is rendered on its own line as `{Display label}: {Formatted value}`.
- Separate meanings remain separate. For example, `Purchase Type: Subscription` and `Sale Event: New sale` are two lines, never one generated sentence.
- Lines remain in the user's saved order. Missing optional values are omitted. The preview body must exactly match the body handed to APNs.

This vocabulary, the exact multiline renderer, and the ordered mapping are locked by backend and iOS model tests. That is the prevention mechanism for the earlier “all fields” ambiguity.

## SERP Store working sample

The current SERP Store test contract contains 17 observed scalar fields. All 17 appear in the designer and start included; the user may hide Payment ID, Currency, or any other field. The 15 business-facing fields are Buyer Email, Checkout Country (IP), Product, Entitlement, Purchase Type, Sale Event, Amount, Dub Affiliate ID, UTM Source, UTM Medium, UTM Campaign, UTM Term, UTM Content, Paid At, and Source Store.

`Checkout Country (IP)` is derived from the checkout request's IP country. It is useful for context but is not a verified billing country; a future `Billing Country` must remain a separate field.

```json
{
  "payment": {
    "id": "cs_live_123",
    "amount_minor": 900,
    "currency": "USD",
    "occurred_at": "2026-08-11T08:27:14Z"
  },
  "buyer": {
    "email": "buyer@example.com",
    "checkout_country_ip": "JP"
  },
  "purchase": {
    "product": "Circle Video Downloader",
    "entitlement": "circle-video-downloader",
    "purchase_type": "subscription",
    "sale_event": "new_sale"
  },
  "attribution": {
    "dub_affiliate_id": "pn_hasanul",
    "utm_source": "dub",
    "utm_medium": "affiliate",
    "utm_campaign": "summer-launch",
    "utm_term": "video downloader",
    "utm_content": "pricing-page"
  },
  "source": {
    "store": "serp.store"
  }
}
```

SERP Store currently has reliable purchase and Dub information. The browser carries the five standard UTM query parameters, but completed orders do not yet reliably persist them; empty UTM values should be omitted until the sender owns that persistence.

## URL lifecycle

The webhook URL is random and stored with the payment source in D1. App builds, Worker deployments, and ordinary code changes do not change it. **Regenerate URL** is the only operation that replaces it, and the UI warns that the previous URL will stop working immediately.

The URL is itself the secret, following the familiar incoming-webhook setup model. It must be treated like a password and pasted only into the sending system's private webhook configuration.

Because the copied developer instructions contain that private URL, they are also a secret. Share them only with the trusted developer working on the sender's private backend. They must not be pasted into public chats, browser code, mobile code, source control, logs, or screenshots.

## Active and paused behavior

- **Active**: valid mapped events become sales and queue notifications.
- **Paused**: new events are acknowledged and ignored; URL, mapping, and history remain.
- Retrying an active event with the same mapped Payment ID never creates a second sale. Once Queue acceptance is recorded it does not enqueue again; crash recovery may enqueue a duplicate message, which resolves to the same sale/device delivery and stable APNs id. Cha-Ching hashes the complete source-scoped ID; long IDs are never truncated before deduplication.
- A stale notification Queue claim is reclaimed after five minutes when the sender retries the same mapped Payment ID; Queue acceptance is recorded only after the send succeeds.
- Numeric Payment IDs are supported only while they are JavaScript-safe integers. Send large IDs as JSON strings, or map a string field, so every digit remains exact for deduplication.

## Privacy and limits

- Payload limit: 64 KiB.
- Setup samples use the existing versioned AES-256-GCM Worker encryption key.
- The sample is deleted when the source is activated.
- Active raw payloads are never persisted.
- Only normalized sale fields and the enabled notification label/value pairs enter history.
- Enabled fields can appear on the iPhone lock screen. The designer warns the user to hide private fields before activation.
- Custom sales are sender-reported. The private URL authenticates the sender but does not provide independent payment-provider verification.
- Malformed JSON is reported as a setup error; active payloads missing a required mapped value are rejected.

## Acceptance criteria

- An authenticated owner can create and list named sources; another user cannot view, change, pause, resume, or regenerate them.
- A private URL remains identical until its owner explicitly regenerates it.
- The app can copy a self-contained developer handoff containing the source name, exact private URL, security boundary, JSON contract, sample payload, setup sequence, expected responses, duplicate-retry check, and completion checklist.
- Setup samples expose selectable scalar paths and values without affecting history or notifications.
- A valid mapping produces a preview before activation.
- Every observed scalar field is present in the notification designer and starts enabled; the UI does not call this a catalog of every theoretically available sender field.
- Connection setup and notification customization are separate screens connected by a clear **Customize notifications** next step.
- The connection screen has no separate **Match the payment** section; required and optional payment mappings remain editable inside Notification settings.
- The main notification list contains every observed field once, shows its display label and example value without a technical source path, and provides a direct on/off switch.
- Tapping a notification row opens rename, remap, and ordering controls. Edit mode also supports drag reordering.
- The exact full notification preview is available behind one tap instead of being duplicated inline with the field list.
- The two test actions are explicit: immediate foreground presentation versus delayed lock-screen delivery. The delayed request returns only after Cloudflare accepts the Queue message, so locking the phone cannot suspend the test send.
- Changing any mapping, label, toggle, order, or amount-format choice invalidates the preview; activation requires the exact mapping that was previewed.
- The title is `Cha-ching!`, and each enabled structured field occupies exactly one ordered `{label}: {value}` line without combining meanings.
- The preview body exactly matches the configured body handed to APNs for a live event.
- An owner-authenticated test action sends the exact current preview to active registered devices, uses the bundled cash-register sound, and creates no payment or payment-history row.
- Active retries are idempotent by the source-scoped mapped Payment ID.
- Pausing and resuming does not replace the URL or erase history.
- Oversized, malformed, or unmappable payloads do not create sales.

## Production status

Migrations `0005` through `0009` and Worker version `5ffd0713-7e1c-4336-8b27-4fa0a55b5732` were deployed on 2026-08-11 JST. The live `serp.store` source remains in setup and its encrypted sample was safely replaced with the 17-field fake payload above; production stayed at 11 sales and 11 deliveries. Migration `0009` adds the normalized notification-field snapshot used for custom pushes. The current Worker also accepts an owner-authenticated delayed sample test, confirms an active registered phone, and places the exact preview body on Cloudflare Queue without creating a payment.

TestFlight build `9` (`ddabb24c-722a-4652-96f4-24ea69577661`) is `VALID` and `IN_BETA_TESTING` in the internal group **Cha-Ching Internal**. It contains the separate Notification settings screen, all-observed-fields list, direct field toggles, rename/remap/reorder editor, deterministic one-field-per-line body, full scrollable foreground test presentation, delayed lock-screen test, cash-register sound, and focused Dashboard/navigation. Final custom-source acceptance still requires opening the existing source on a signed iPhone, testing both sampled presentations, activating it, then replaying one real sender payment and observing one matching payment and notification.
