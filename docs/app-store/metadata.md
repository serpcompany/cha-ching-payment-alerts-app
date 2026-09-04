# App Store Metadata

App Store Connect app ID: `6800029282`. Version `1.0` is `PREPARE_FOR_SUBMISSION`; submission `41946309-b89e-438e-92f4-974499de05f7` has unresolved review issues. Apple first rejected the 13-inch iPad marketing composition under Guideline 2.3.3; it was replaced with three native 2064×2752 app screenshots before the 2026-08-27 resubmission. Apple later rejected the app version under Guidelines 5.6 and 5.1.1(ix). The purchase-consent remediation is implemented in repository source, while Apple's organization-account requirement remains an external release gate.

Build `37` (`e5a23ec9-7a7d-4b8c-85bb-de2c09261541`) is the latest valid TestFlight build but is superseded as an App Review candidate while the dashboard paging regression is repaired. Build 30 introduced explicit purchase consent before StoreKit while preserving the annual trial, purchase and restore gate, backend-owned Apple transaction reconciliation, transaction-update handling, passive receiver-side custom-webhook activity evidence, authenticated account deletion and legal surfaces, and the complete Payments feed. Build 28 passed the signed-iPhone launch acceptance on an iPhone 17 Pro Max running iOS 26.6. TestFlight build 23 previously reconciled an Apple-signed sandbox transaction end to end; production product-access enforcement is enabled from that evidence.

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

Version `1.0`, build `28`, the `Cha-Ching Full Access` subscription group, and the first `Cha-Ching Annual` subscription were submitted together to App Review on 2026-08-12 at 15:38:30 UTC. After the Guideline 2.3.3 screenshot rejection, the app-version item was repaired while both subscription items remained attached and ready for review; the same submission was resubmitted on 2026-08-27. Apple rejected the app version again on 2026-08-31 under Guidelines 5.6 and 5.1.1(ix). The replacement purchase flow adds an explicit pre-StoreKit confirmation that repeats the no-charge-today, annual-price, renewal, and cancellation terms. Guideline 5.1.1(ix) separately requires submission by an Apple Developer Program organization rather than the current individual account; that membership change is a release gate outside the app binary.

The final package includes the required iPhone screenshot set and three 13-inch iPad screenshots that show the actual app in use, a 1024×1024 annual-subscription promotional image, the Free app price tier, published App Privacy answers, active commercial agreements, and reviewer instructions. The subscription validator reports no blocking issues. Listing copy does not imply that PayPal alerts are supported in version 1.0.

Build `30` was signed manually with active provisioning profile `Cha-Ching App Store Push` because Xcode's cached interactive Apple Account session remains expired. The profile contains production APNs and Sign in with Apple entitlements. The already distribution-signed archive was packaged as an IPA without re-signing, then its build number, production API URL, local-catalog exclusion, entitlements, signature, and ZIP integrity were verified before upload through the App Store Connect API key. Apple processed it as `VALID` with non-exempt encryption set to false. Simulator QA also verified that **Not now** dismisses the new confirmation without invoking StoreKit and **Continue to Apple** opens Apple's protected purchase flow. Build 21 previously confirmed the same protected StoreKit boundary on a physical device and exposed the restore regression fixed in build 22.

Apple limits both the localized app name and subtitle to 30 characters. Reference: [App Store Connect app information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/).
