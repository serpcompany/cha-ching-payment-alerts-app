# App Store Metadata

App Store Connect app ID: `6800029282`. Version `1.0` is `WAITING_FOR_REVIEW` in submission `41946309-b89e-438e-92f4-974499de05f7`. Apple rejected the first review on 2026-08-26 under Guideline 2.3.3 because the 13-inch iPad screenshot was marketing artwork rather than a full-screen view of the app. The rejected image was replaced with three native 2064×2752 captures of the Dashboard, a payment detail, and Connect; all three assets completed processing before the existing submission was resubmitted on 2026-08-27 at 03:24:16 UTC.

TestFlight build `28` (`939edae1-3975-42df-b5d8-1665c5a7d7bc`) is valid, `IN_BETA_TESTING`, and is the App Review release candidate. It includes the annual StoreKit trial, purchase and restore gate, backend-owned Apple transaction reconciliation, transaction-update handling, passive receiver-side custom-webhook activity evidence, authenticated account deletion and legal surfaces, and a Dashboard that presents every payment currently loaded from the sales API instead of stopping after six rows. Build 28 passed the signed-iPhone launch acceptance on an iPhone 17 Pro Max running iOS 26.6. TestFlight build 23 previously reconciled an Apple-signed sandbox transaction end to end; production product-access enforcement is enabled from that evidence. Builds `1` through `27` are superseded for launch review.

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

Version `1.0`, build `28`, the `Cha-Ching Full Access` subscription group, and the first `Cha-Ching Annual` subscription were submitted together to App Review on 2026-08-12 at 15:38:30 UTC. After the Guideline 2.3.3 screenshot rejection, the app-version item was repaired and marked resolved while both subscription items remained attached and ready for review. The same submission `41946309-b89e-438e-92f4-974499de05f7` was resubmitted on 2026-08-27 at 03:24:16 UTC and is `WAITING_FOR_REVIEW`.

The final package includes the required iPhone screenshot set and three 13-inch iPad screenshots that show the actual app in use, a 1024×1024 annual-subscription promotional image, the Free app price tier, published App Privacy answers, active commercial agreements, and reviewer instructions. The subscription validator reports no blocking issues. Listing copy does not imply that PayPal alerts are supported in version 1.0.

Build `28` was signed manually with active provisioning profile `Cha-Ching App Store Push` because Xcode's cached interactive Apple Account session remains expired. The profile contains production APNs and Sign in with Apple entitlements. The already distribution-signed archive was packaged as an IPA without re-signing, then its build number, production API URL, local-catalog exclusion, entitlements, signature, dollar-icon metadata, and ZIP integrity were verified before upload through the App Store Connect API key. Apple processed it as `VALID` with non-exempt encryption set to false and made it available to the internal group with focused account-deletion test notes. Build 21 previously confirmed that a physical-device tap presents Apple's protected StoreKit purchase surface and exposed the restore regression fixed in build 22.

Apple limits both the localized app name and subtitle to 30 characters. Reference: [App Store Connect app information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/).
