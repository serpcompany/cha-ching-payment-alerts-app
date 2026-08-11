# App Store Metadata

App Store Connect app ID: `6800029282`. Version `1.0` exists in `PREPARE_FOR_SUBMISSION`; it must not be submitted until the production authentication/provider flows and Apple readiness checks pass.

TestFlight build `6` (`f08e77af-a753-4867-913d-6579a9f43ad5`) is valid and attached to the internal group `Cha-Ching Internal` (`483e4a13-43c0-4658-9c1b-8238e7b9a773`). It includes production APNs, universal custom webhook sources, a copyable AI-agent/developer handoff, and an all-fields notification designer with per-field visibility, editable labels, remapping, and exact preview. Builds `1` through `5` are superseded.

The external group `Cha-Ching Beta` (`e95c8fca-3141-4ccb-917f-e7910bc37e0d`) contains `farleythecoder@gmail.com`, and build 6 is attached. The English What to Test notes and privacy URL are configured. External availability still requires Apple's beta review; required beta-review contact details, including the phone number, must be supplied before review can be submitted. Apple does not send the usable external invitation until that review is approved.

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

Build `6` was signed manually with active provisioning profile `Cha-Ching App Store Push` because Xcode's cached interactive Apple Account session is expired. The profile contains production APNs and Sign in with Apple entitlements. The signed archive was packaged without macOS resource-fork metadata and uploaded with the App Store Connect API key; Apple processed it as `VALID` with non-exempt encryption set to false.

Apple limits both the localized app name and subtitle to 30 characters. Reference: [App Store Connect app information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/).
