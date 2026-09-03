# Payment dashboard patterns

Researched on 2026-09-03 from first-party Stripe, Square, and Shopify
documentation. This note separates observed product behavior from a recommendation
for Cha-Ching.

## Sourced patterns

### Stripe Dashboard mobile app

- Stripe's web Dashboard separates **Home**, which holds business-performance
  analytics/charts and important notifications, from **Transactions**, which
  holds the detailed, filterable payment list. [Stripe: Web
  Dashboard](https://docs.stripe.com/dashboard/basics)
- Stripe's mobile Home page uses customizable charts. Users can add, remove, and
  reorder them; the app also keeps payment lists and payment detail screens as
  distinct navigation surfaces. Stripe lists daily gross volume, daily net
  volume, and daily new payments among its mobile metrics. [Stripe: Dashboard
  mobile app](https://docs.stripe.com/dashboard/mobile)
- Stripe displays Home-chart values in the account's default currency. When an
  account receives multiple currencies, Stripe estimates a combined value using
  sample exchange rates and warns that it will not exactly match settlement.
  [Stripe: Dashboard mobile app](https://docs.stripe.com/dashboard/mobile)
- Stripe's account timezone is configurable. The Dashboard timezone changes
  displayed times, while API timestamps remain UTC; Stripe separately warns that
  switching timezone boundaries between reporting periods can make transactions
  appear duplicated or omitted. [Stripe: customize the Dashboard
  timezone](https://support.stripe.com/questions/customize-the-time-zone-on-the-dashboard)
  and [Stripe: timezone changes to
  reports](https://support.stripe.com/questions/time-zone-customization-changes-to-reports)
- Stripe treats refunds as payment-management activity and shows them on an
  individual successful payment. Its Balance Summary accounts for charges,
  refunds, disputes, adjustments, and fees when explaining balance movement.
  [Stripe: Dashboard mobile app](https://docs.stripe.com/dashboard/mobile) and
  [Stripe: Balance summary report](https://docs.stripe.com/reports/balance)

### Square

- Square's mobile sales report opens on today's sales activity, with preset and
  custom ranges. Its summary/trend metric choices include gross sales, net sales,
  average sale, and order count. [Square: sales summaries and
  reports](https://squareup.com/help/us/en/article/5381-in-app-summaries-and-reports)
- Square exposes top items and top categories from the mobile report, while its
  payment-method report separately defines payment count, payment amount, refund
  count, refund amount, total collected, fees, and net total. This keeps gross,
  refunds, and net values visibly distinct. [Square: sales summaries and
  reports](https://squareup.com/help/us/en/article/5381-in-app-summaries-and-reports)
- Square stores timezone as an account preference. [Square: edit account and
  business information](https://squareup.com/help/us/en/article/3861-edit-your-account-and-business-settings)

### Shopify

- Shopify's overview uses numeric metric cards, graphs where appropriate, an
  optional comparison with the preceding period, and a dashboard-level display
  currency selector. Its mobile Analytics surface defaults to Today compared
  with Yesterday, while the general overview documentation describes a 90-day
  default; presets include Today and custom fixed or rolling ranges. [Shopify:
  Analytics overview dashboard](https://help.shopify.com/en/manual/reports-and-analytics/shopify-reports/overview-dashboard/using-the-overview-dashboard)
- Shopify's sales family distinguishes gross sales, net sales, order count, and
  average order value. Its product report breaks total sales down by product and
  preserves the product information recorded at the time of sale. [Shopify:
  sales reports](https://help.shopify.com/en/manual/reports-and-analytics/shopify-reports/report-types/default-reports/sales-report)
- Shopify's report language supports an IANA timezone for day boundaries, and
  its dashboard currency conversion uses the historical rate from the date of
  each transaction. [ShopifyQL timezone
  semantics](https://help.shopify.com/en/manual/reports-and-analytics/shopify-reports/report-types/shopifyql-editor/shopifyql-syntax)
  and [Shopify: Analytics overview
  dashboard](https://help.shopify.com/en/manual/reports-and-analytics/shopify-reports/overview-dashboard/using-the-overview-dashboard)

## Connection navigation in comparable products

### Sourced facts

- Stripe's documented mobile surfaces focus on repeated operational work: Home
  charts, payment and customer lists/details, balances, search, and a global add
  action. Its web Dashboard groups account and product configuration under
  Settings. Stripe does not document payment-source setup as a primary mobile
  tab. [Stripe: Dashboard mobile
  app](https://docs.stripe.com/dashboard/mobile) and [Stripe: Web Dashboard
  settings](https://docs.stripe.com/dashboard/basics#dashboard-settings)
- Square lets users place up to four frequently used tools in the Dashboard
  app's bottom navigation and leaves the rest under **More**. In the Square app,
  linked bank-account management is reached through **More > Settings > Account
  > Bank account**. [Square: customize the Dashboard
  app](https://squareup.com/help/us/en/article/5618-get-started-with-the-square-dashboard-app)
  and [Square: link and edit transfer
  methods](https://squareup.com/help/us/en/article/3896-link-and-edit-your-bank-account)
- Shopify mobile puts payment-provider activation under **Menu > Settings >
  Payments** and sales-channel add/remove management under **Menu > Settings >
  Sales channels**. Active channel performance can still be viewed from Shopify
  Home; connection management itself remains a settings task. [Shopify:
  additional payment
  methods](https://help.shopify.com/en/manual/payments/additional-payment-methods/activate-payment-methods)
  and [Shopify: managing sales
  channels](https://help.shopify.com/en/manual/online-sales-channels/manage)
- RevenueCat configures outbound integrations per project from the dashboard's
  **Integrations** section rather than presenting connection setup as a primary
  analytics destination. Its Stripe Billing connection is likewise documented
  as configuration performed in the dashboard. [RevenueCat:
  integrations](https://www.revenuecat.com/docs/integrations/integrations) and
  [RevenueCat: Stripe Billing](https://www.revenuecat.com/docs/web/integrations/stripe)

### Cha-Ching recommendation (inference)

Use three stable primary tabs: **Home**, **Payments**, and **Settings**. Put a
**Payment sources** row in Settings that opens a source list; place **Add payment
source** and per-source connect, pause, configure, and disconnect actions on that
drill-down screen. Surface source problems on Home or with a Settings badge when
they need attention. This preserves visibility without making an occasional
setup/maintenance task a permanent tab. This recommendation is an inference from
the comparable products above, not a rule stated by any one source.

## Apple-native building blocks

### Sourced facts

- Apple defines a tab bar as navigation between top-level app sections, advises
  using it for navigation rather than actions, and notes that fewer tabs are
  generally easier to navigate. [Apple HIG: Tab
  bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars)
- `NavigationStack` and `NavigationLink` provide the standard push-and-back
  hierarchy for moving from a root screen to detail screens. A SwiftUI `Form`
  applies platform-appropriate styling to grouped settings controls. [Apple:
  `NavigationStack`](https://developer.apple.com/documentation/swiftui/navigationstack)
  and [Apple: `Form`](https://developer.apple.com/documentation/swiftui/form)
- Apple describes `Picker` as the native mutually exclusive selection control.
  The navigation-link picker style pushes a list of choices and is suitable for
  a large set; inside a navigation stack, Apple says the default menu style is
  preferred unless a pushed list better fits the choice set. [Apple:
  `Picker`](https://developer.apple.com/documentation/swiftui/picker) and [Apple:
  navigation-link picker
  style](https://developer.apple.com/documentation/swiftui/pickerstyle/navigationlink)
- Apple uses time ranges as an example of an appropriate segmented control, but
  recommends no more than about five segments on iPhone. [Apple HIG: Segmented
  controls](https://developer.apple.com/design/human-interface-guidelines/segmented-controls)
- Swift Charts provides native `Chart` and `LineMark` building blocks, automatic
  scales and axes, localization, and accessibility support. Apple's chart
  guidance recommends common chart types, simple presentations, gradual detail,
  and accessible descriptions. [Apple: Swift
  Charts](https://developer.apple.com/documentation/charts), [Apple:
  `LineMark`](https://developer.apple.com/documentation/charts/linemark), and
  [Apple HIG: Charting
  data](https://developer.apple.com/design/human-interface-guidelines/charting-data)
- `GroupBox` is the system SwiftUI container for visually collecting a logical
  group of content with an optional label. [Apple:
  `GroupBox`](https://developer.apple.com/documentation/swiftui/groupbox)

### Cha-Ching recommendation (inference)

- Implement the main hierarchy with SwiftUI `TabView` for **Home**, **Payments**,
  and **Settings**, and a `NavigationStack` within each tab.
- Build Settings with `Form`, `Section`, and `NavigationLink`. Use a native
  `Picker` for the account timezone; an IANA timezone list is too large for a
  segmented control and suits a pushed, searchable selection list.
- Do not reproduce the screenshot's seven ranges as one iPhone segmented
  control. Use a native menu-style `Picker` showing the selected range, or show
  at most the most-used ranges in a segmented picker and put the complete set in
  a native menu. The former preserves every requested range without custom
  control design.
- Build trend cards with `GroupBox` or straightforward SwiftUI grouping and use
  Swift Charts `Chart` plus `LineMark` for current and previous periods. Prefer
  system typography, spacing, colors, SF Symbols, axes, and accessibility over a
  bespoke card/chart framework. Custom styling should be limited to Cha-Ching's
  established brand tokens.

## Options for Cha-Ching

The repository currently defines the first tab as a payments-only **Dashboard**,
with the full payment feed and no summary widgets. That local product state is
recorded in [Dashboard, Navigation, and Notification Brand](../features/dashboard-navigation-and-brand.md).
Whether the new summary replaces that definition, extends it, or introduces a
separate Home tab is a Cha-Ching decision; the market examples support both
combined mobile summaries and separate overview/transaction surfaces.

## User-provided Stripe reference

The user provided a Stripe mobile Home screenshot as the visual and information-
architecture reference for Cha-Ching's first dashboard. It shows:

- separate **Home** and **Payments** tabs;
- a **Today** summary containing **Gross volume**, **Payments**, and **Customers**;
- report periods for **1W**, **4W**, **1Y**, **MTD**, **QTD**, **YTD**, and **All**;
- current-versus-previous comparison values, percentage changes, and line charts;
- report cards for **Gross volume**, **Monthly recurring revenue**, and
  **Active subscribers**; and
- an **Edit** action for report customization.

This is reference evidence, not an instruction to reproduce Stripe branding or
to display metrics Cha-Ching cannot calculate truthfully. Cha-Ching already
normalizes successful-payment amount, currency, occurrence time, and a product
label, so gross payment volume, payment count, product breakdown, and their time
series are supportable. It does not currently normalize customer identity or
subscription lifecycle state. Consequently, unique customers, monthly recurring
revenue, and active subscribers need additional source contracts and domain
decisions before they can be accurate.

## Current Cha-Ching analytics inputs

The normalized `sales` record currently retains payment source and account,
provider event and payment IDs, amount in minor units, currency, status, product
label, optional plan and sale-type labels, optional country, a subscription flag,
payment time, and selected custom-webhook notification fields. The Stripe path
currently supplies amount, currency, event time, optional billing country, and
whether the charge references an invoice; it deliberately uses the generic
product label **Stripe payment** and does not retain customer name or email.

| Dashboard information | Can Cha-Ching calculate it now? | Important boundary |
| --- | --- | --- |
| Gross payment volume | Yes | Keep currencies separate unless an explicit conversion model is added. |
| Payment count | Yes | Count normalized successful payments after source-scoped idempotency. |
| Time series and prior-period change | Yes | Calculate against all matching D1 rows; the phone feed is capped at the latest 100. |
| By payment source | Yes | Stripe, PayPal, and custom are normalized source types. |
| By country | Partially | Country is optional and may be missing. |
| By product | Partially | Custom sources can map a useful product label; Stripe currently becomes **Stripe payment**. |
| Recurring-payment volume/count | Partially | `is_subscription` identifies an invoice-backed or mapped recurring payment, not lifecycle state. |
| Unique customers | No | There is no normalized cross-source customer identity. |
| Monthly recurring revenue | No | Successful payments alone do not establish current recurring commitments, cancellations, pauses, or plan changes. |
| Active subscribers | No | Cha-Ching does not ingest subscription lifecycle state. |
| Net revenue, fees, refunds, disputes, or balance | No | Those adjustments are not ingested consistently across sources. |

An optional HMAC-based customer fingerprint derived from a normalized customer
email could enable privacy-reduced unique-customer counting without retaining the
raw address in the analytics record. It would still require a new Stripe field,
a custom-webhook customer mapping, a privacy-contract update, key-management and
normalization rules, and explicit behavior when identity is missing. It could be
supporting evidence for possible cross-source duplicates, but email plus amount
must not become an automatic silent-merge rule because legitimate repeated
purchases can share both values.

### Option A — smallest useful summary (recommended first)

Keep the existing payment list as the Dashboard's main content and add a compact
summary above it:

1. A shared period control: **Today**, **7 days**, **30 days**, and **All**.
2. Two headline values for that period: **Payment volume** and **Payments**.
3. A short **By product** breakdown with product label, payment count, and gross
   amount, followed immediately by **Payments**.

This matches the common mobile hierarchy without implying accounting-grade net
revenue. It also maps to data Cha-Ching already records: successful-payment
amount, currency, product label, and event time.

### Option B — richer business pulse

Add **Average payment**, previous-period change, a small trend chart, source
filtering, and a ranked top-products card. These are familiar patterns, but they
add comparison rules, empty/sparse-data behavior, chart work, and more pressure
to define currency conversion. They can follow after Option A proves useful.

### Option B2 — separate Home overview

Add **Home** as a separate overview tab and retain **Dashboard** (or rename it
**Payments**) as the complete feed. Stripe's web product follows this separation.
It gives the summary room to grow, but four bottom tabs and two adjacent
high-level destinations may be heavier than an indie-founder alert app needs.
This should be tested against the actual current app before choosing it.

### Option C — accounting-style summary

Show gross volume, refunds, fees, disputes, and net volume. Stripe and Square make
these separate concepts, but Cha-Ching should not offer this option until it
ingests each adjustment consistently across every source. Otherwise “net” would
look authoritative while being incomplete.

## Recommended semantics

- **Default period:** Today. Cha-Ching is a notification-first mobile app, so the
  Square-style daily pulse is a closer fit than Shopify's analysis-oriented
  90-day default. Persist the user's last selected period if repeated switching
  becomes common; this is a product recommendation, not a sourced industry rule.
- **Timezone:** Initialize an account-level Dashboard timezone from the device's
  current IANA timezone, expose a selector in Settings, and then keep that choice
  stable until the user changes it. Display the selected zone near the date
  control or in its sheet. Store source timestamps in UTC and apply the chosen
  timezone only when defining period boundaries. Do not silently follow travel
  after the initial choice.
- **Headline amount:** Call the initial value **Payment volume** or **Gross
  payments**, not revenue, earnings, balance, or net. It is the sum of normalized
  successful payments received by Cha-Ching during the selected period.
- **Count:** Label it **Payments** and count normalized payment records in the same
  period. Avoid “orders” or “sales” unless the domain later guarantees that one
  payment equals one order or sale.
- **Products:** Rank by gross payment amount by default and show count alongside
  it. Group missing or generic labels under **Unknown product** rather than
  dropping them. A payment-level product label is not necessarily a line-item
  catalog, so avoid quantities or variants until source data supports them.
- **Currencies:** In the first version, show a separate total for each currency.
  Do not combine currencies until Cha-Ching has an explicit conversion source,
  rate timestamp, display currency, and an “estimated” label. Stripe and Shopify
  both disclose conversion behavior; an unexplained combined number would hide
  materially important assumptions.
- **Refunds:** Do not subtract refunds from the headline until refund events are
  ingested consistently. When that exists, keep **Gross payments**, **Refunds**,
  and **Net payments** separately visible, following the Stripe/Square distinction.
- **Placement:** Put the period control and the two-value summary directly above
  the payment list. Put the product breakdown between the summary and list only
  when it has meaningful data; keep it short and offer drill-down later. If the
  product goal is a distinct overview experience, use Option B2 and rename the
  current list surface **Payments** rather than leaving both Home and Dashboard
  ambiguous.

## Decisions still needed before implementation

1. Is the first release Option A, and is the product breakdown included in that
   first slice or deferred behind the two headline values?
2. Should the Dashboard remember the last period, or deliberately reopen on
   Today every time?
3. Is timezone a user/account setting shared by all sources, or does any real use
   case require per-source timezones?
4. Should the product ranking default to payment volume, payment count, or let the
   user switch between them?
5. For currencies, is one card per encountered currency acceptable, and what cap
   should apply before the UI collapses into a “Multiple currencies” detail?
