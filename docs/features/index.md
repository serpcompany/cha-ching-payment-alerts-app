# Feature Index

| Feature | Status | Document |
| --- | --- | --- |
| Sign in with Apple | Implemented; real device flow plus isolated local Simulator sessions | `sign-in-with-apple.md` |
| Stripe account connection | Read-only live Stripe App installed; production sandbox guard verified | `provider-account-connections.md` |
| PayPal account connection | Implemented for sandbox, live approval pending | `provider-account-connections.md` |
| Feature entitlements | Implemented | `entitlements.md` |
| Dashboard, navigation, and notification brand | Payments-only MVP dashboard, concurrent-refresh fix, actionable refresh errors, device toggle, crash-safe notification details, non-sticky icon badge, delayed lock test, and dollar icon available in internal TestFlight build 15 | `dashboard-navigation-and-brand.md` |
| Stripe payment ingestion and notifications | Real live Charge persisted and visibly notified on a signed iPhone | `sale-ingestion-and-notifications.md` |
| Custom webhook payment sources | Production sender event received; always-visible activation and notification setup available in internal TestFlight build 15; first active live payment acceptance pending | `custom-webhook-payment-sources.md` |
| PayPal payment ingestion and notifications | Not implemented | `sale-ingestion-and-notifications.md` |

“Implemented” describes repository behavior. “Live” requires the production checks tracked in [GitHub Issue #1](https://github.com/serpcompany/cha-ching/issues/1).
