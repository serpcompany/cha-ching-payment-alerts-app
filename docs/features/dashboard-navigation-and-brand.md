# Home Dashboard, Navigation, and Notification Brand

## User outcome

Cha-Ching separates the payment-performance overview from individual transactions. **Home** answers “how are payments going?”, **Payments** retains the normalized transaction feed and detail screens, and **Settings** contains preferences and payment-source management.

## Navigation

The signed-in app has exactly three top-level tabs:

1. **Home** — a timezone-aware payment-performance overview.
2. **Payments** — the existing transaction list and payment details.
3. **Settings** — Payment sources, reporting timezone, notifications, subscription, account, and legal actions.

Settings → **Payment sources** contains the existing Stripe, PayPal, and custom-webhook connection flows. It is not a top-level tab. Payment notifications select Payments and open the matching detail. Source-health notifications select Settings and push Payment sources; the app opens the affected source only after an owner-scoped load succeeds. A transient failure preserves the route with Retry, while a confirmed missing source ends it with an unavailable message.

## Home dashboard

The top daily-summary card uses the saved reporting timezone and shows Gross volume, Payments, and Average payment. It opens on **Today**. Swiping left (or choosing Previous day) walks backward one complete local calendar day at a time; swiping right (or choosing Next day) walks forward and stops at Today. Historical days use their full timezone-local midnight-to-midnight window, including daylight-saving transitions, while Today ends at generation time. Counts may span currencies; monetary totals and averages never do.

Reports default to **4 weeks**. A native menu offers 1 week, 4 weeks, 1 year, month to date, quarter to date, year to date, and all time. Gross volume and Payments include current and previous values, percentage-change state, and current/previous Swift Charts line series. Product and payment-source sections show both payment count and gross amount for the selected currency; neither value mixes currencies.

Gross volume is the sum of normalized succeeded payments. It is not revenue, earnings, net, or a balance. Setup samples, ignored events, retries, refunded rows, and source-scoped duplicates do not count. Refunds are excluded rather than subtracted because complete adjustment ingestion is not available. Product grouping uses the retained label, including the honest generic `Stripe payment` label. Custom-source grouping uses the user-defined source name.

V1 deliberately excludes Customers, MRR, active subscribers, balances, fees, refunds, disputes, net revenue, source filtering, report customization, and currency conversion because the normalized payment model does not support those claims.

## Time boundaries and comparisons

- Today starts at local midnight and ends at generation time.
- 1 week and 4 weeks start at local midnight six and 27 calendar days ago.
- 1 year starts on the matching local calendar date one year ago, clamped for leap day.
- MTD, QTD, and YTD start at the local calendar boundary.
- All starts at the earliest qualifying payment and has no previous comparison.
- Other previous periods use the immediately preceding equal-elapsed interval.
- A positive value over zero displays **New**; zero over zero displays an em dash; zero after a positive value displays `-100%`.
- Daily, weekly, monthly, and adaptive all-time buckets include explicit zeros. A timezone that skips midnight uses the first valid instant on that local date.

The phone's current IANA timezone initializes the account preference once. The first device wins atomically. Travel does not silently move report boundaries. A searchable Settings selector explicitly changes it and immediately refreshes Home.

## Payments

Payments presents exactly the latest-100 response from `/v1/sales` in server order and opens the existing detail screen. A notification for a payment outside that page uses the exact, user-scoped `/v1/sales/:id` response only as navigation detail; it does not insert that payment into, resize, or reorder the feed. A confirmed missing payment ends the route. A temporary request failure keeps the notification route and presents native Retry and Dismiss actions: Retry repeats exact resolution, while only explicit Dismiss consumes the unresolved route. Pull-to-refresh keeps loaded rows on failure, provides Retry and Dismiss, and shares an in-flight request across concurrent callers.

Foreground payment delivery and successful source-history clearing publish the same neutral payment-history-changed event. Payments and Home independently coalesce bursts and mark an in-flight snapshot dirty so one trailing refresh follows it, ensuring a stale pre-event response cannot win and removed rows leave totals and charts as well as the list.

## Native design

The app uses Apple's `TabView`, one `NavigationStack` per tab, `Form`, `Section`, `NavigationLink`, `LabeledContent`, native `Picker` styles, searchable `List`, `GroupBox`, `ContentUnavailableView`, `ProgressView`, `.refreshable`, SF Symbols, Dynamic Type, and Swift Charts. Cha-Ching's mint and gold theme remains an accent; there is no custom tab bar, chip control, timezone control, or chart engine.

## Settings and notification identity

Payment notifications remain an explicit device preference. Settings retains restore/manage subscription, notification registration guidance, sign out, account deletion, support, privacy, and terms. The dollar-symbol app icon, `Cha-ching!` title, cash-register sound, non-sticky badge behavior, and Apple-controlled banner presentation remain unchanged.

## Acceptance criteria

- Tabs are Home, Payments, and Settings in that order.
- Payment sources is reachable under Settings with all existing setup and management actions.
- Home derives its Today and reporting boundaries from the saved account timezone.
- Home's daily summary swipes backward through prior local days and forward only as far as Today.
- Dashboard totals come from one transactional D1 aggregate batch and keep currencies separate.
- Home supports every approved period, prior comparisons, zero-filled charts, product grouping, and source grouping.
- Loaded Home data survives refresh failure with Retry and Dismiss actions.
- Payment and source-health notifications reach their new destinations.
- Payment list/detail, notification settings, subscription, account deletion, and legal flows remain reachable.
