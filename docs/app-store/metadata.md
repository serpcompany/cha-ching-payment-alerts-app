# App Store Metadata

App Store Connect app ID: `6800029282`. Version `1.0`, build `38`, and the existing three-item submission `41946309-b89e-438e-92f4-974499de05f7` are `WAITING_FOR_REVIEW` after resubmission on 2026-09-04 at 00:25:27 UTC. Apple first rejected the 13-inch iPad marketing composition under Guideline 2.3.3; it was replaced with three native 2064×2752 app screenshots before the 2026-08-27 resubmission. Apple later rejected the app version under Guidelines 5.6 and 5.1.1(ix). Build 38 contains the purchase-consent remediation and the verified dashboard paging repair. Apple's organization-account requirement did not block API resubmission but remains an external review risk until Apple confirms it is satisfied.

Build `38` (`4fea4548-ddb8-42c6-ae8e-7f2c4f273946`) is `VALID`, `IN_BETA_TESTING` in **Cha-Ching Internal**, attached to App Store version `1.0`, and is the current review candidate. It was built from canonical `main` commit `a050f36`, tagged `v1.0.0`, and includes the native iPad screenshots, explicit purchase consent, responsive two-metric summary cards, and stable one-day dashboard paging. Build 28 passed the signed-iPhone launch acceptance on an iPhone 17 Pro Max running iOS 26.6. TestFlight build 23 previously reconciled an Apple-signed sandbox transaction end to end; production product-access enforcement is enabled from that evidence. Builds `1` through `37` are superseded for launch review.

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

Version `1.0`, the `Cha-Ching Full Access` subscription group, and the first `Cha-Ching Annual` subscription were submitted together to App Review on 2026-08-12 at 15:38:30 UTC. After the Guideline 2.3.3 screenshot rejection, the app-version item was repaired while both subscription items remained attached and ready for review; the same submission was resubmitted on 2026-08-27. Apple rejected the app version again on 2026-08-31 under Guidelines 5.6 and 5.1.1(ix). For the 2026-09-04 resubmission, build 38 replaced build 30, reviewer notes were updated, the rejected app-version item was marked resolved, and all three preserved items returned to `READY_FOR_REVIEW` before the existing submission was submitted. The version and submission then reached `WAITING_FOR_REVIEW` with zero reported blockers.

The final package includes the required iPhone screenshot set and three 13-inch iPad screenshots that show the actual app in use, a 1024×1024 annual-subscription promotional image, the Free app price tier, published App Privacy answers, active commercial agreements, and reviewer instructions. The subscription validator reports no blocking issues. Listing copy does not imply that PayPal alerts are supported in version 1.0.

Build `38` was signed manually with the active `Apple Distribution` identity and `Cha-Ching App Store Push` provisioning profile because Xcode's cached interactive Apple Account session remains expired. The profile contains production APNs, Sign in with Apple, and `beta-reports-active` entitlements. The already distribution-signed archive was packaged as an IPA without re-signing after Xcode export hit the documented account-session `Copy failed` path. Verification confirmed bundle ID `com.serpcompany.chaching`, version/build `1.0 (38)`, the production API URL, excluded local StoreKit catalog, dollar app icon, entitlements, strict code signature, no resource-fork metadata, ZIP integrity, and SHA-256 `c43eb9d6404eec4af9fde58637f6597c0344e0092e07424f19c3bf05126ff3e5`. Apple processed it as `VALID` with encryption exempt. The full iOS suite passed 80 tests with one intentional skip; focused paging stress, real Dashboard delayed-success/failure integration, an unsigned Release build, 101 backend tests, and both GitHub CI jobs also passed.

Apple limits both the localized app name and subtitle to 30 characters. Reference: [App Store Connect app information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/).
