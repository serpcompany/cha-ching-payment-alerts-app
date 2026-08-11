# Dashboard, Navigation, and Notification Brand

## User outcome

Cha-Ching opens into one clear **Dashboard** for current revenue and payments. Connection management and Settings remain separate destinations; duplicate history and processor summaries do not compete with the primary payment view.

## Navigation

The signed-in app has exactly three tabs:

1. **Dashboard** — today's revenue summary and payments.
2. **Connect** — Stripe, PayPal, and custom payment-source setup and management.
3. **Settings** — payment-notification status and account sign-out.

There is no separate **History** tab. The Dashboard's **Payments** section is the user-facing payment list and opens the existing payment-detail screen. The former **Today** tab and navigation title are both renamed **Dashboard**.

## Dashboard content

- The hero uses **Notifications on/off**, never “Pings on/off.”
- The MVP Dashboard contains only the revenue-today hero and **Payments**. It has no **Top seller**, **This week**, or **Last 7 days** widget, and the unused chart/stat components and aggregations do not remain in the app target.
- **Connected processors** is removed; connection status belongs in **Connect**.
- **Recent pings** becomes **Payments**.
- The empty state says **No payments yet** and explains that a payment will appear when one arrives.
- Payment rows and details continue to use the D1-backed sales API; this is a language and information-architecture change, not a second data source.

## Settings content

- **Payment notifications** is an actual on/off toggle. Turning it off unregisters this iPhone from Cha-Ching's backend and stops automatic re-registration; turning it on requests system permission when needed and registers the phone again.
- If backend removal fails, Settings reports that the phone could not be removed instead of claiming a successful server-side disable. iOS system permission remains controlled separately in the Settings app.
- **Plan access** is removed. Entitlements remain enforced invisibly by the Worker and still determine which connection actions are allowed.
- Sign out remains available.

## Notification identity

- The app icon and in-app brand mark use a bold dollar symbol, not a checkmark.
- The compiled primary icon is named `ChaChingDollarIcon`; release QA verifies both the archived app icon and Apple's processed build icon before a TestFlight handoff.
- Remote payment notifications and sample-based test notifications use the bundled cash-register sound by default.
- If the user's device is muted, Focus blocks the alert, notification permission is off, or iOS suppresses sound, Cha-Ching cannot override that system behavior.
- While Cha-Ching is open, the app suppresses the compact system banner and presents a full, scrollable notification sheet containing every selected structured line. The payment list still refreshes.
- **Test lock screen** schedules the sample from the Worker through Cloudflare Queue with a short delay, then tells the user to lock the phone. Because the Worker owns the delay, locking the app cannot suspend the outgoing request.

## Acceptance criteria

- The tab bar contains Dashboard, Connect, and Settings in that order, with no History or Today tab.
- Dashboard contains no Connected processors section and no user-facing use of “ping.”
- Dashboard contains no Top seller, This week, or Last 7 days widget or implementation.
- Dashboard contains a Payments section backed by the same payment list and detail route.
- Settings contains a working Payment notifications toggle and Sign out, with no Plan access section.
- A foreground sample push exposes every selected line in a scrollable in-app presentation; a lock-screen test is queued only after the server accepts the delayed request.
- The compiled app includes matching dollar-symbol app-icon and BrandMark assets.
- The compiled app bundle includes the named cash-register sound used by both live and test APNs payloads.
