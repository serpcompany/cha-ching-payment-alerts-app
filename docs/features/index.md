# Feature Index

| Feature | Status | Document |
| --- | --- | --- |
| Sign in with Apple | Implemented; real device flow plus isolated local Simulator sessions | `sign-in-with-apple.md` |
| Stripe account connection | Read-only live Stripe App installed; production sandbox guard verified | `provider-account-connections.md` |
| PayPal account connection | Implemented for sandbox, live approval pending | `provider-account-connections.md` |
| Feature entitlements | Implemented | `entitlements.md` |
| Stripe sale ingestion and pings | Real live Charge persisted and visibly notified on a signed iPhone | `sale-ingestion-and-pings.md` |
| Custom webhook payment sources | Production Worker deployed; separate all-fields Notification settings UI implemented after build 6; signed-device source acceptance pending | `custom-webhook-payment-sources.md` |
| PayPal sale ingestion and pings | Not implemented | `sale-ingestion-and-pings.md` |

“Implemented” describes repository behavior. “Live” requires the production checks tracked in [GitHub Issue #1](https://github.com/serpcompany/cha-ching/issues/1).
