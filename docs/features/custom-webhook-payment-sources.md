# Custom Webhook Payment Sources

## User outcome

A signed-in user can connect any store or payment system that can send JSON to a webhook, without Cha-Ching needing provider-specific code.

## Setup experience

1. Tap **Connect another payment source** and give it a recognizable name.
2. Copy either the private webhook URL or **Copy instructions for developer**. The copied instructions include the URL, security rules, request contract, setup steps, test expectations, retry check, and completion checklist.
3. The source starts at **Waiting for first event**. Ask the developer to send one representative event containing the fields the user may want, then tap **Check for event** in Cha-Ching.
4. After the Worker receives that event, the source shows **Event received** and its real receipt time. Cha-Ching does not preload a mock event in production.
5. Tap **Customize notifications** to move to a separate **Notification settings** screen. Payment matching and notification design live there; the connection screen does not contain a separate **Match the payment** section.
6. Confirm or adjust Payment ID, Amount, Currency, amount format, and optional payment mappings in the notification-settings experience.
7. Every observed scalar field appears once and starts on. The compact ordered list shows only the user-facing label, example value, and direct on/off switch. Tap a row to rename it, remap it, or move it; the technical source path appears only inside that detail screen.
8. Tap **Preview notification** to review the exact multiline body. **Test notification** sends that same observed event immediately as a genuine Apple notification without creating a payment. Apple's abbreviated preview shows only a few lines. Pressing a setup test opens its full standalone preview because no payment exists; pressing an active-source test selects Dashboard and opens the latest retained payment detail. **Test lock screen** asks the Worker to queue the exact observed event for a short delay and immediately shows inline guidance to lock the iPhone; no OK button delays the countdown. **Activate payment source** remains in the preview.

The sender owns the payload shape. Cha-Ching discovers every scalar value actually present in a valid sample payload up to 64 KiB and saves the user's mapping and notification design. A sample received during setup is never counted as revenue and never sends a notification. Changing a field toggle, label, mapping, or order invalidates the old preview, so activation always uses the design currently visible on screen.

The selected UI is Variant A from the throwaway [notification-settings prototype](https://github.com/serpcompany/cha-ching/tree/prototype/notification-settings-variants/prototypes/notification-settings-prototype). The prototype branch records the design decision and is not merged into the product branch.

## Screen model and interaction rules

The MVP keeps payment-source connection and notification design as two distinct jobs:

1. **Connect tab** — shows one card per custom source with its name and honest connection state: **Waiting for first event**, **Event received**, **Receiving events**, **Needs checking**, or **Paused**. Configuration state and observed webhook health remain separate: an enabled URL can need checking when requests stop arriving or are rejected.
2. **Payment-source setup** — creates the source, exposes the durable private URL and developer instructions, and checks for a sample. It does not contain payment-field pickers or notification rows.
3. **Notification settings** — opens from the dedicated **Customize notifications** next step after a sample is found. It owns both payment matching and notification design, shows the source as connected, provides preview and test actions, and contains an ordered list with every observed field exactly once.
4. **Field row** — shows only the display label, sample value, disclosure indicator, and a direct on/off switch. The section header shows the current included count, such as **15 of 17 on**.
5. **Edit detail** — tapping a row opens its focused editor. The user can show or hide the line, rename its display label, remap it to any observed payload field, inspect the example and technical path, move it earlier or later, and see that line's preview. The main list also supports drag reordering through **Edit**.
6. **Notification preview and device test** — Preview notification shows an iPhone-style preview containing the exact title, line order, labels, and sample values that will be sent. The adjacent Test notification action sends that design through APNs using the cash-register sound and reports whether a registered device accepted it. **Activate payment source** remains an explicit confirmation of the previewed design.
7. **Active-source management** — reopening an activated source provides pause/resume, URL copy, developer-prompt copy, explicit URL regeneration, and notification presentation editing. The MVP applies renaming, hiding, reordering, and re-enabling to retained Dashboard values as well as future payments. Values enabled when a payment arrived remain archived by stable field ID when later hidden, so repeated off/on edits are reversible. A newly shown field appears on an older payment only when the value was retained when it arrived; Cha-Ching never invents or recovers discarded raw values. Preview, immediate test, and lock-screen test remain available after activation; tests use the latest saved payment values when available and safe example values otherwise. Active edits remain a local draft until the Worker accepts them; returning to management then shows **Notification settings saved.** Remapping remains a setup-only action because the raw setup sample is deleted at activation.

The Notification settings screen always pins **Activate payment source** above the bottom edge. It is visibly disabled with guidance until payment matching is complete and the current choices have been previewed. Previewing never hides activation inside the preview sheet: the user closes the preview, sees the enabled activation action in the same place, and explicitly puts the source live. Once active, new unique webhook events create Dashboard payments and notifications.

The notification screen deliberately avoids repeating technical source paths or a full preview beneath every row. Technical details are disclosed only when editing a field, and the complete notification appears in one dedicated preview. The MVP does not include search or filtering; the compact ordered list is the current all-fields navigation model.

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

The agreed SERP Store sender contract contains 17 scalar fields. When SERP Store sends them in its first real event, all 17 appear in the designer and start included; the user may hide Payment ID, Currency, or any other field. The 15 business-facing fields are Buyer Email, Checkout Country (IP), Product, Entitlement, Purchase Type, Sale Event, Amount, Dub Affiliate ID, UTM Source, UTM Medium, UTM Campaign, UTM Term, UTM Content, Paid At, and Source Store.

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
- **Receiving events**: Cha-Ching has recent request evidence. The source-management screen shows the last webhook request and last accepted payment independently.
- **Needs checking — rejected**: the latest request reached Cha-Ching but could not satisfy the saved mapping. The UI shows a safe mapping error without exposing raw payload values.
- **Needs checking — quiet**: an established source has received no request within three times its median recent payment interval, bounded between six hours and seven days. This is evidence that deserves checking, not proof that the sender is disconnected.
- **Check for new webhook activity**: reloads the latest request evidence; Cha-Ching cannot probe or reconnect the external sender. The result interprets the returned evidence instead of merely confirming the API request. An unchanged quiet or rejected warning explicitly remains **Needs checking** and explains the sender-side next step. A later accepted request explicitly clears the prior warning. Failure appears in the same section and preserves the last known evidence. Paused sources do not offer the activity check.
- Sources with fewer than three retained payments do not get silence-based outage guesses. They continue to show the evidence Cha-Ching actually has.
- The scheduled health monitor sends one Apple notification per uninterrupted warning state. Pressing it opens Connect and the affected source. A later accepted event or duplicate clears the warning latch so a future outage can notify again.
- Retrying an active event with the same mapped Payment ID never creates a second sale. Once Queue acceptance is recorded it does not enqueue again; crash recovery may enqueue a duplicate message, which resolves to the same sale/device delivery and stable APNs id. Cha-Ching hashes the complete source-scoped ID; long IDs are never truncated before deduplication.
- A stale notification Queue claim is reclaimed after five minutes when the sender retries the same mapped Payment ID; Queue acceptance is recorded only after the send succeeds.
- Numeric Payment IDs are supported only while they are JavaScript-safe integers. Send large IDs as JSON strings, or map a string field, so every digit remains exact for deduplication.

## Privacy and limits

- Payload limit: 64 KiB.
- Setup samples use the existing versioned AES-256-GCM Worker encryption key.
- The sample is deleted when the source is activated.
- After activation, authenticated presentation-only edits preserve the fixed field IDs and payload paths. Renaming, hiding, reordering, and re-enabling update the presentation of existing payment details. A value that was enabled when the payment arrived remains in a private ID-keyed archive when later hidden, making repeated off/on edits reversible; a value never retained at arrival cannot be recovered. Future payments and notifications use the same accepted presentation.
- Active raw payloads are never persisted.
- Only normalized sale fields and notification values enabled when the payment arrived enter history. Later hiding changes presentation but does not erase that retained value; account deletion and source-history clearing remove it with the payment.
- Enabled fields can appear on the iPhone lock screen. The designer warns the user to hide private fields before activation.
- Custom sales are sender-reported. The private URL authenticates the sender but does not provide independent payment-provider verification.
- Malformed JSON is reported as a setup error; active payloads missing a required mapped value are rejected.

## Acceptance criteria

- An authenticated owner can create and list named sources; another user cannot view, change, pause, resume, or regenerate them.
- A private URL remains identical until its owner explicitly regenerates it.
- The app can copy a self-contained developer handoff containing the source name, exact private URL, security boundary, JSON contract, sample payload, setup sequence, expected responses, duplicate-retry check, and completion checklist.
- Setup samples expose selectable scalar paths and values without affecting history or notifications.
- A new production source contains no fabricated setup event. It remains **Waiting for first event** until its private URL receives a valid sender POST, then shows **Event received** with the actual receipt time; activation changes it to **Active**.
- A valid mapping produces a preview before activation.
- Every observed scalar field is present in the notification designer and starts enabled; the UI does not call this a catalog of every theoretically available sender field.
- Connection setup and notification customization are separate screens connected by a clear **Customize notifications** next step.
- The connection screen has no separate **Match the payment** section; required and optional payment mappings remain editable inside Notification settings.
- The main notification list contains every observed field once, shows its display label and example value without a technical source path, and provides a direct on/off switch.
- Tapping a notification row opens rename, remap, and ordering controls. Edit mode also supports drag reordering.
- The exact full notification preview is available behind one tap instead of being duplicated inline with the field list.
- The two test actions are explicit: immediate foreground presentation versus delayed lock-screen delivery. The delayed request returns only after Cloudflare accepts the Queue message, starts the countdown immediately, and shows nonmodal lock guidance, so locking the phone cannot suspend the test send and no acknowledgement is required.
- Changing any mapping, label, toggle, order, or amount-format choice invalidates the preview; activation requires the exact mapping that was previewed.
- The title is `Cha-ching!`, and each enabled structured field occupies exactly one ordered `{label}: {value}` line without combining meanings.
- The preview body exactly matches the configured body handed to APNs for a live event.
- An owner-authenticated test action is available during setup and after activation. It sends the exact current presentation to active registered devices, uses the latest saved payment values when available (or safe example values otherwise), links to that latest payment for Dashboard drill-down when one exists, uses the bundled money sound, and creates no payment or payment-history row.
- A real payment may omit display-only fields that appeared in the setup sample, such as UTM attribution. Cha-Ching still accepts the payment and preserves the selected order while leaving those absent rows out of that notification. Required Payment ID, Amount, and Currency mapping failures still reject the event.
- Rejected active events emit a safe `custom.webhook.rejected` Worker log containing the source ID and mapping reason, never the raw payload or field values.
- Source APIs return health separately from configured status, including safe detail, last webhook request, last accepted payment, and an expected-activity deadline when cadence is established.
- Checking for new webhook activity shows an explicit in-progress state and then reports the returned health outcome. Transport success is never presented as connection success: unchanged quiet or rejected evidence remains warning-styled and actionable, recovered activity explicitly clears the warning, and a failed check does not erase the previously displayed evidence. The refreshed detail also updates the source shown on the parent Connect screen.
- An established quiet source and a source whose latest valid JSON request is rejected show **Needs checking**; an active source with insufficient cadence history is never falsely labeled disconnected from silence alone.
- A connection-health push contains the affected source ID, and pressing it opens that source's management UI.
- Active retries are idempotent by the source-scoped mapped Payment ID.
- Pausing and resuming does not replace the URL or erase history.
- An active or paused source can preview, test, rename, show, hide, re-enable, and reorder its mapped notification fields without another sample; repeated hide/show edits restore retained historical values. It cannot remap payload paths after activation.
- Cancelling or failing an active-source save leaves the persisted configuration unchanged. A successful authenticated save reads back the accepted mapping and shows an explicit confirmation on the source-management screen.
- Setup cannot dead-end after customization: **Activate payment source** remains visible, explains what is missing, and enables only for the exact mapping the user previewed.
- Oversized, malformed, or unmappable payloads do not create sales.

## Production status

Migrations `0005` through `0009` and Worker version `6d0c1df3-79ba-42ca-b038-153b02d7ebc0` were deployed on 2026-08-11 JST. The production `serp.store` sender delivered a real setup event at `2026-08-11 08:55:11` UTC; the source now truthfully reports **Event received**, retains its existing private URL, has one active iPhone, and awaits explicit mapping preview and activation. Production still has zero custom-source payments and deliveries. The Worker returns `waiting`, `event_received`, `active`, or `paused` as an explicit connection state and does not set a synthetic unread badge on pushes. Migration `0009` adds the normalized notification-field snapshot used for custom pushes. The Worker also accepts an owner-authenticated delayed setup-event notification test, confirms an active registered phone, and places the exact preview body on Cloudflare Queue without creating a payment.

TestFlight build `15` (`939afd51-c83a-4f3f-8028-a91b2bc548c8`) is `VALID` and `IN_BETA_TESTING` in the internal group **Cha-Ching Internal**. It contains the explicit **Waiting for first event** → **Event received** → **Active** flow, separate Notification settings, pinned activation guidance/action, all-observed-fields list, direct field toggles, rename/remap/reorder editor, deterministic one-field-per-line body, genuine Apple notifications with crash-safe cold-launch full details, delayed lock-screen testing, non-sticky icon badges, cash-register sound, and focused Dashboard/navigation.

On 2026-08-11 at 19:16 JST, the first real payment after the `serp.store` sender deployment reached Cha-Ching three times but received HTTP 422 because attribution fields that existed in the setup sample were absent from the real event. Worker version `094b0852-7314-4479-94b7-0b69259e6aaa` corrected that contract: display-only fields are optional per payment. A production smoke event with attribution deliberately absent then returned 202, created one D1 payment, reached Queue acceptance, and produced one APNs `sent` delivery on the first attempt. The diagnostic payment and delivery were removed after verification. The original rejected payment requires a sender replay because raw active payloads are intentionally not retained.

On 2026-08-12 JST, migration `0010` reconciled all 11 retained custom-payment detail presentations with the source's accepted active settings: each retains six or seven available current details and zero stale disabled details. Worker version `b10a3922-5a67-4da1-b9a1-4847dc58754b` keeps future active-source edits synchronized with history and enables active/paused preview and test delivery from the latest retained payment values, with safe example values when no payment exists. TestFlight `1.0 (18)` contains the matching always-available active-source controls.

Worker version `c52144ab-a5f2-44ba-bdfb-91913c75d2e0` was deployed on 2026-08-12 JST. Active-source test notifications now carry the latest retained payment ID, so pressing one follows the normal Dashboard payment drill-down. Setup tests remain standalone previews because no payment exists yet.

TestFlight `1.0 (19)` (`f976c0ef-9fa6-40b1-8a38-8e82f8f9bd8f`) is `VALID` and `IN_BETA_TESTING` in **Cha-Ching Internal**. It contains the approved replacement money sound, immediate nonmodal lock-screen countdown guidance, active-test Dashboard routing, and relevant configurable custom-payment row subtitles.

Migration `0011` and Worker version `7017202c-0764-459b-b8cf-d2cce5479e27` were deployed on 2026-08-12 JST. All 11 retained production custom payments now have stable ID-keyed value archives with 9–10 recoverable fields and no missing archive. Presentation saves no longer destroy a hidden value, so later re-enabling reliably restores it when the payment retained that value at arrival.

TestFlight `1.0 (20)` (`8d66944d-8c80-4f93-9657-aa5d5fa274f4`) is `VALID` and `IN_BETA_TESTING` in **Cha-Ching Internal**. It reads an open payment detail from the refreshed shared Payments store and adds native pull-to-refresh to that screen.

Custom-source activity evidence, adaptive quiet-source monitoring, one-time health notifications, and the iOS **Connection health** UI are implemented in the repository with migration `0012`. They have not been deployed or promoted to TestFlight.
