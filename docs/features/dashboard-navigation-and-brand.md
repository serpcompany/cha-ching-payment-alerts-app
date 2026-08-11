# Dashboard, Navigation, and Notification Brand

## User outcome

Cha-Ching opens into one clear **Dashboard** for current revenue and payments. Connection management and Settings remain separate destinations; duplicate history and processor summaries do not compete with the primary payment view.

## Navigation

The signed-in app has exactly three tabs:

1. **Dashboard** — current revenue, supporting metrics, chart, and payments.
2. **Connect** — Stripe, PayPal, and custom payment-source setup and management.
3. **Settings** — payment-notification status and account sign-out.

There is no separate **History** tab. The Dashboard's **Payments** section is the user-facing payment list and opens the existing payment-detail screen. The former **Today** tab and navigation title are both renamed **Dashboard**.

## Dashboard content

- The hero uses **Notifications on/off**, never “Pings on/off.”
- **Connected processors** is removed; connection status belongs in **Connect**.
- **Recent pings** becomes **Payments**.
- The empty state says **No payments yet** and explains that a payment will appear when one arrives.
- Payment rows and details continue to use the D1-backed sales API; this is a language and information-architecture change, not a second data source.

## Settings content

- The notification row is labeled **Payment notifications**.
- **Plan access** is removed. Entitlements remain enforced invisibly by the Worker and still determine which connection actions are allowed.
- Sign out remains available.

## Notification identity

- The app icon and in-app brand mark use a bold dollar symbol, not a checkmark.
- Remote payment notifications and sample-based test notifications use the bundled cash-register sound by default.
- If the user's device is muted, Focus blocks the alert, notification permission is off, or iOS suppresses sound, Cha-Ching cannot override that system behavior.

## Acceptance criteria

- The tab bar contains Dashboard, Connect, and Settings in that order, with no History or Today tab.
- Dashboard contains no Connected processors section and no user-facing use of “ping.”
- Dashboard contains a Payments section backed by the same payment list and detail route.
- Settings contains Payment notifications and Sign out, with no Plan access section.
- The compiled app includes matching dollar-symbol app-icon and BrandMark assets.
- The compiled app bundle includes the named cash-register sound used by both live and test APNs payloads.
