# Dashboard, Navigation, and Notification Brand

## User outcome

Cha-Ching opens into one clear **Dashboard** for payments. Connection management and Settings remain separate destinations; speculative metrics, duplicate history, and processor summaries do not compete with the primary payment view.

## Navigation

The signed-in app has exactly three tabs:

1. **Dashboard** — payments reported by active sources.
2. **Connect** — Stripe, PayPal, and custom payment-source setup and management.
3. **Settings** — payment-notification controls and account sign-out.

There is no separate **History** tab. The Dashboard's **Payments** section is the user-facing payment list and opens the existing payment-detail screen. The former **Today** tab and navigation title are both renamed **Dashboard**.

## Dashboard content

- The MVP Dashboard contains only **Payments**. It has no revenue hero, notification bell, **Top seller**, **This week**, or **Last 7 days** widget, and those unused dashboard components and aggregations do not remain in the app target.
- **Connected processors** is removed; connection status belongs in **Connect**.
- **Recent pings** becomes **Payments**.
- The empty state says **No payments yet** and explains that a payment will appear when one arrives.
- Payment rows and details continue to use the D1-backed sales API. A historical custom payment retains the values that were enabled when it arrived in a stable field-ID archive, while accepted presentation edits rename, hide, reorder, and re-enable those values so Dashboard details stay consistent with the source's current configuration. Newly shown fields appear on an older payment only when the value was retained when it arrived; Stripe payments retain the normalized fallback details.
- Pulling down on an individual payment detail refreshes the shared Payments feed and redraws that open detail from the latest server-accepted presentation instead of preserving the navigation-time snapshot.
- A custom-payment row uses the product title, a dollar-payment symbol, and the first enabled configured detail as its subtitle. It does not substitute a generic globe or “Reported by” attribution. Changing the enabled fields, labels, or order therefore changes the most prominent supporting detail on retained custom payments after the accepted presentation is applied.
- If Payments cannot refresh, already-loaded payments stay visible. A compact inline message says **Payments couldn't refresh.**, offers **Retry** and **Dismiss**, and clears automatically after a successful refresh.
- Automatic foreground, notification-triggered, and pull-to-refresh callers share one in-flight Payments request. A canceled or superseded caller does not flash a false connectivity error while the shared request is still succeeding.

## Settings content

- **Payment notifications** is an actual on/off toggle. Turning it off unregisters this iPhone from Cha-Ching's backend and stops automatic re-registration; turning it on requests system permission when needed and registers the phone again.
- The toggle is the status. Settings does not repeat it with a separate **Status** row.
- If backend removal fails, Settings reports that the phone could not be removed instead of claiming a successful server-side disable. iOS system permission remains controlled separately in the Settings app.
- **Plan access** is removed. Entitlements remain enforced invisibly by the Worker and still determine which connection actions are allowed.
- Sign out remains available.

## Notification identity

- The app icon and in-app brand mark use a bold dollar symbol, not a checkmark.
- The compiled primary icon is named `ChaChingDollarIcon`; release QA verifies both the archived app icon and Apple's processed build icon before a TestFlight handoff.
- Remote payment notifications and sample-based test notifications use the bundled money sound by default. The checked-in CAF preserves the decoded audio from the approved `cha-ching-money.mp3` source while using an Apple notification-compatible format.
- Payment pushes do not set a synthetic unread badge. Opening or returning to Cha-Ching, including by pressing a notification, clears any badge left by an older build.
- If the user's device is muted, Focus blocks the alert, notification permission is off, or iOS suppresses sound, Cha-Ching cannot override that system behavior.
- While Cha-Ching is open, the app requests Apple's real banner, list, sound, and badge presentation. It does not automatically substitute an in-app sheet.
- Apple controls the abbreviated foreground and lock-screen layout and documents it as title, subtitle, and two to four body lines. Pressing a real payment notification selects Dashboard and opens that D1-backed payment detail, whether Cha-Ching was open, backgrounded, or not running. A setup test notification has no payment and therefore keeps the standalone preview sheet.
- **Test lock screen** schedules the sample from the Worker through Cloudflare Queue with a short delay, then immediately shows nonmodal inline guidance to lock the phone. No acknowledgement button gates or obscures the countdown. Because the Worker owns the delay, locking the app cannot suspend the outgoing request.

## Acceptance criteria

- The tab bar contains Dashboard, Connect, and Settings in that order, with no History or Today tab.
- Dashboard contains no Connected processors section and no user-facing use of “ping.”
- Dashboard contains no Top seller, This week, or Last 7 days widget or implementation.
- Dashboard contains no revenue hero or nonfunctional notification-bell toolbar item.
- Dashboard contains a Payments section backed by the same payment list and detail route.
- An open payment detail supports pull-to-refresh and displays the refreshed server copy of that payment.
- A custom-payment row uses a payment symbol and its first enabled configured detail; it never shows the generic globe or “Reported by” fallback.
- A Payments refresh failure is actionable and dismissible and does not erase previously loaded payments.
- Pulling to refresh while another automatic refresh is active does not issue duplicate requests or briefly show a false failure card.
- Settings contains a working Payment notifications toggle and Sign out, with no Plan access section.
- A setup sample push is a genuine Apple banner and opens its standalone preview after a press because no payment exists yet. An active-source test uses the latest retained payment ID, so pressing it safely selects Dashboard and opens that payment's full detail just like a real payment notification. A lock-screen test is queued only after the server accepts the delayed request and starts its countdown without an acknowledgement step.
- The compiled app includes matching dollar-symbol app-icon and BrandMark assets.
- The compiled app bundle includes the named cash-register sound used by both live and test APNs payloads.
