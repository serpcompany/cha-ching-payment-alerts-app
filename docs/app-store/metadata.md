# App Store Metadata

App Store Connect app ID: `6800029282`. Version `1.0` exists in `PREPARE_FOR_SUBMISSION`; it must not be submitted until the production authentication/provider flows and Apple readiness checks pass.

TestFlight build `1` (`e0ee6056-0423-449e-9173-11eaa182bfca`) is valid and assigned to the internal group `Cha-Ching Internal` (`483e4a13-43c0-4658-9c1b-8238e7b9a773`). The account holder is invited as an internal tester.

## Primary English (US)

- App Store name: **Cha-Ching: Payment Alerts** (25/30 characters)
- Subtitle: **Get Notified When You Get Paid** (30/30 characters)
- Installed app name: **Cha-Ching**
- Primary category: Business
- Secondary category: Finance

The App Store name and subtitle intentionally split the longer SEO phrase across two indexed fields while staying within Apple's 30-character limits. Do not repeat `Cha-Ching`, `payment`, `alerts`, `notified`, `paid`, or the company name in the keyword field.

## Product language

- One-line promise: Know the moment you get paid.
- Promotional line: Connect Stripe and PayPal, then let Cha-Ching keep the moment visible.
- MVP disclaimer: Account connection is live first; verified sale ingestion and push notifications must not be advertised as available until their feature acceptance criteria pass.

## URLs

- Marketing and support: `https://cha-ching-api.serpcompany.workers.dev/`
- Privacy policy: `https://cha-ching-api.serpcompany.workers.dev/privacy`
- Terms: `https://cha-ching-api.serpcompany.workers.dev/terms`

Canonical machine-readable listing metadata lives under `metadata/`.

## Submission status

The App Store Connect record and version metadata are staged. Apple validation currently has four listing/build blockers:

- the valid TestFlight build must be attached to App Store version `1.0`;
- at least one required iPhone screenshot set must be uploaded;
- review contact details and honest reviewer instructions must be supplied;
- launch territories and App Privacy answers must be confirmed.

Do not submit version `1.0` for review until Sign in with Apple and both provider connection paths pass the production acceptance checks in GitHub Issue #1. The App Store name and subtitle promise payment alerts, so review submission also requires either verified notification behavior or revised listing copy that describes the connection-only MVP.

The first TestFlight archive was signed manually with provisioning profile `Cha-Ching App Store` because Xcode's cached interactive Apple Account session had expired. The installed Apple Distribution identity and App Store Connect API credentials remain sufficient for deterministic archive and upload automation.

Apple limits both the localized app name and subtitle to 30 characters. Reference: [App Store Connect app information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/).
