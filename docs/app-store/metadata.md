# App Store Metadata

App Store Connect app ID: `6800029282`. Version `1.0` exists in `PREPARE_FOR_SUBMISSION`; it must not be submitted until the production authentication/provider flows and Apple readiness checks pass.

TestFlight build `28` (`939edae1-3975-42df-b5d8-1665c5a7d7bc`) is valid and attached to the internal group `Cha-Ching Internal` (`483e4a13-43c0-4658-9c1b-8238e7b9a773`). It adds authenticated account deletion with fresh Sign in with Apple authorization, Apple credential revocation before complete D1 cleanup, explicit Apple-billing separation, and reachable Cha-Ching-specific support, privacy, and terms surfaces. TestFlight build 23 previously reconciled an Apple-signed sandbox transaction end to end; production product-access enforcement is enabled from that evidence. Builds `1` through `27` are superseded for internal testing.

The external group `Cha-Ching Beta` (`e95c8fca-3141-4ccb-917f-e7910bc37e0d`) contains `farleythecoder@gmail.com`, and build 8 remains attached. Build 27 is internal-only until the missing beta-review contact details are supplied. The English What to Test notes and privacy URL are configured. External availability still requires Apple's beta review; the submission attempted on 2026-08-11 was rejected because required beta-review contact details, including the phone number, are missing. Apple does not send the usable external invitation until those details are supplied and the review is approved.

## Primary English (US)

- App Store name: **Cha-Ching: Payment Alerts** (25/30 characters)
- Subtitle: **Get Paid. Hear the Cha-Ching.** (28/30 characters)
- Installed app name: **Cha-Ching**
- Primary category: Business
- Secondary category: Finance

The App Store name carries the searchable product category while the subtitle carries the approved celebration line within Apple's 30-character limit. Do not repeat `Cha-Ching`, `payment`, `alerts`, `paid`, or the company name in the keyword field.

## Product language

- One-line promise: Know the moment you get paid.
- Promotional line: Get notified when you make money from apps, software, digital products, affiliate sales, and more.
- MVP disclaimer: Stripe alerts have passed a real live-charge and signed-iPhone notification check. Custom-webhook payments are sender-reported rather than provider-verified. PayPal is not a launch payment source.

## URLs

- Marketing and support: `https://cha-ching-api.serpcompany.workers.dev/`
- Privacy policy: `https://cha-ching-api.serpcompany.workers.dev/privacy`
- Terms: `https://cha-ching-api.serpcompany.workers.dev/terms`
- In-app support: `https://cha-ching-api.serpcompany.workers.dev/support`

The app, privacy disclosures, and reviewer notes must use these Cha-Ching-specific Worker pages. Generic corporate legal pages do not describe Cha-Ching's custom webhook payload handling, Apple subscription boundary, or immediate authenticated account deletion and are not an equivalent substitute.

Canonical machine-readable listing metadata lives under `metadata/`.

## Submission status

The App Store Connect record and version metadata are staged. Apple validation currently has four listing/build blockers:

- the valid TestFlight build must be attached to App Store version `1.0`;
- at least one required iPhone screenshot set must be uploaded;
- review contact details and honest reviewer instructions must be supplied;
- launch territories and App Privacy answers must be confirmed.

Do not submit version `1.0` for App Store review until Sign in with Apple and both provider connection paths pass the remaining production acceptance checks in GitHub Issue #1. Stripe's real webhook and signed-device notification checks now pass. Listing copy must not imply that PayPal alerts are supported in version 1.0.

Build `28` was signed manually with active provisioning profile `Cha-Ching App Store Push` because Xcode's cached interactive Apple Account session remains expired. The profile contains production APNs and Sign in with Apple entitlements. The already distribution-signed archive was packaged as an IPA without re-signing, then its build number, production API URL, local-catalog exclusion, entitlements, signature, dollar-icon metadata, and ZIP integrity were verified before upload through the App Store Connect API key. Apple processed it as `VALID` with non-exempt encryption set to false and made it available to the internal group with focused account-deletion test notes. Build 21 previously confirmed that a physical-device tap presents Apple's protected StoreKit purchase surface and exposed the restore regression fixed in build 22. The sandbox sheet omitted the app icon even though App Store Connect processed the build's real 1024×1024 primary icon, so that cosmetic issue remains a pre-release metadata check rather than an app-asset blocker.

Apple limits both the localized app name and subtitle to 30 characters. Reference: [App Store Connect app information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/).
