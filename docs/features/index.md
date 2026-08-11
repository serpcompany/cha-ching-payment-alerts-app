# Feature Index

| Feature | Status | Document |
| --- | --- | --- |
| Sign in with Apple | Implemented; real device flow plus isolated local Simulator sessions | `sign-in-with-apple.md` |
| Stripe account connection | Read-only live Stripe App installed; production sandbox guard verified | `provider-account-connections.md` |
| PayPal account connection | Implemented for sandbox, live approval pending | `provider-account-connections.md` |
| Feature entitlements | Implemented | `entitlements.md` |
| Dashboard, navigation, and notification brand | Focused MVP dashboard, device toggle, full foreground details, delayed lock test, and verified dollar icon available in internal TestFlight build 9 | `dashboard-navigation-and-brand.md` |
| Stripe payment ingestion and notifications | Real live Charge persisted and visibly notified on a signed iPhone | `sale-ingestion-and-notifications.md` |
| Custom webhook payment sources | Production Worker deployed; immediate full-detail and delayed lock-screen tests available in internal TestFlight build 9; signed-device source acceptance pending | `custom-webhook-payment-sources.md` |
| PayPal payment ingestion and notifications | Not implemented | `sale-ingestion-and-notifications.md` |

“Implemented” describes repository behavior. “Live” requires the production checks tracked in [GitHub Issue #1](https://github.com/serpcompany/cha-ching/issues/1).
