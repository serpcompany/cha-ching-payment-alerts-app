# App Store Metadata

App Store Connect app ID: `6800029282`. Version `1.0` exists in `PREPARE_FOR_SUBMISSION`; it must not be submitted until the production authentication/provider flows and Apple readiness checks pass.

TestFlight build `14` (`65aee6a4-7236-447e-93a9-488d050ebdd5`) is valid, `IN_BETA_TESTING`, and attached to the internal group `Cha-Ching Internal` (`483e4a13-43c0-4658-9c1b-8238e7b9a773`). It makes custom-source activation permanently visible after preview, reduces the MVP Dashboard to Payments only, replaces vague refresh failures with Retry/Dismiss while preserving loaded rows, and adds an explicitly confirmed Stripe history-clear action that preserves the connection and paused setting. It retains the honest real-event webhook states, non-sticky badge, crash-safe full notification details, genuine Apple notification surfaces, per-device switch, delayed lock-screen test, and dollar-symbol icon. Builds `1` through `13` are superseded for internal testing.

The external group `Cha-Ching Beta` (`e95c8fca-3141-4ccb-917f-e7910bc37e0d`) contains `farleythecoder@gmail.com`, and build 8 remains attached. Build 14 is internal-only until the missing beta-review contact details are supplied. The English What to Test notes and privacy URL are configured. External availability still requires Apple's beta review; the submission attempted on 2026-08-11 was rejected because required beta-review contact details, including the phone number, are missing. Apple does not send the usable external invitation until those details are supplied and the review is approved.

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
- MVP disclaimer: Stripe alerts have passed a real live-charge and signed-iPhone notification check. PayPal is account linking only in version 1.0.

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

Do not submit version `1.0` for App Store review until Sign in with Apple and both provider connection paths pass the remaining production acceptance checks in GitHub Issue #1. Stripe's real webhook and signed-device notification checks now pass. Listing copy must not imply that PayPal alerts are supported in version 1.0.

Build `14` was signed manually with active provisioning profile `Cha-Ching App Store Push` because Xcode's cached interactive Apple Account session is expired. The profile contains production APNs and Sign in with Apple entitlements. The already distribution-signed archive was packaged as an IPA, then its build number, entitlements, signature, and ZIP integrity were verified before upload through the App Store Connect API key. Apple processed it as `VALID` with non-exempt encryption set to false and made it available to the internal group.

Apple limits both the localized app name and subtitle to 30 characters. Reference: [App Store Connect app information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/).
