# Apple subscriptions and launch compliance for Cha-Ching

Research date: 2026-08-11

## Question

What current Apple rules and App Store Connect configuration apply to Cha-Ching selling an auto-renewing subscription with a seven-day trial, including In-App Purchase eligibility, disclosure, restoration, cancellation, entitlement state, review notes, privacy, account deletion, and the connection of external Stripe and custom-webhook payment sources?

## Decision summary

Cha-Ching should sell its v1 access through one Apple auto-renewable In-App Purchase subscription group. The seven-day trial should be a **one-week free introductory offer** configured in App Store Connect. The customer opts into the subscription through Apple's purchase sheet; access begins immediately and the standard localized renewal price is charged after the trial unless the customer cancels. Apple supports a one-week free introductory offer, and a customer can redeem only one introductory offer per subscription group. The app must check Apple's eligibility instead of promising a trial to every returning customer. [Apple: introductory offers](https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-introductory-offers-for-auto-renewable-subscriptions/) [Apple: offer durations](https://developer.apple.com/help/app-store-connect/reference/pricing-and-availability/in-app-purchase-and-subscriptions-pricing-and-availability) [Apple: eligibility API](https://developer.apple.com/documentation/storekit/product/subscriptioninfo/iseligibleforintrooffer)

Stripe and custom webhooks may remain v1 payment **data-source connections**. They must not be used to sell or unlock Cha-Ching, and the app must not portray “Connect Stripe” as an alternative checkout. Cha-Ching's paid digital functionality is unlocked only by StoreKit. The safest review position is that Cha-Ching observes seller-authorized payment events and sends notifications; it does not initiate, receive, hold, transmit, refund, or otherwise manage the user's money. This distinction matters because Apple requires In-App Purchase for in-app digital functionality and separately subjects financial trading, investing, or money-management apps to institutional and licensing expectations. [Apple: App Review Guidelines 3.1 and 3.2.1(viii)](https://developer.apple.com/app-store/review/guidelines/)

## Required subscription setup

### Commercial account readiness

Before the subscription can be sold, the Apple Account Holder must have an active Paid Apps Agreement. Apple also requires banking details and the applicable tax forms to receive proceeds. These are launch gates, not code tasks. [Apple: sign and update agreements](https://developer.apple.com/help/app-store-connect/manage-agreements/sign-and-update-agreements/) [Apple: banking information](https://developer.apple.com/help/app-store-connect/manage-banking-information/enter-banking-information/) [Apple: tax information](https://developer.apple.com/help/app-store-connect/manage-tax-information/provide-tax-information)

### App Store Connect product

The launch configuration needs:

- one subscription group;
- at least one auto-renewable subscription product with a stable product identifier;
- a selected duration, localized display name and description, localized price, storefront availability, and review screenshot/notes;
- a one-week **Free Trial** introductory offer for the launch storefronts;
- the first subscription and its new subscription group included with the app version in the first review submission.

Apple permits SaaS subscriptions when they provide ongoing value, last at least seven days, and work across the user's devices. The exact standard billing cadence and price remain a product decision; the seven-day trial is compatible with Apple's available free-offer durations. [Apple: App Review Guidelines 3.1.2](https://developer.apple.com/app-store/review/guidelines/) [Apple: create subscriptions](https://developer.apple.com/help/app-store-connect/manage-subscriptions/offer-auto-renewable-subscriptions/) [Apple: first subscription submission](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase)

### Paywall and trial disclosure

Before invoking the Apple purchase flow, the user must be able to understand:

- the subscription name and standard billing duration;
- exactly which Cha-Ching services are included;
- that the first seven days are free only when Apple says the account is eligible;
- the full, localized amount and cadence charged when the trial ends;
- that the subscription automatically renews until canceled;
- how to restore and manage/cancel the subscription;
- the Terms of Use and Privacy Policy.

Price strings should come from StoreKit rather than being hard-coded. Apple specifically says the signup screen must show the name, duration, included service, localized billing amount, and a restore/sign-in route, and that a free-trial screen must clearly state the trial duration and the amount billed afterward. `SubscriptionStoreView` can provide localized product presentation and policy links, but using it does not remove the need to verify the complete experience. [Apple Human Interface Guidelines: In-App Purchase](https://developer.apple.com/design/human-interface-guidelines/in-app-purchase) [Apple: `Product`](https://developer.apple.com/documentation/storekit/product) [Apple: `SubscriptionStoreView`](https://developer.apple.com/documentation/storekit/subscriptionstoreview)

## Entitlement and billing-state contract

Cha-Ching should keep its existing rule that feature access is server-owned, but the grant must be derived from verified Apple transaction/subscription state rather than from UI state or a purchase-success response alone.

Recommended contract:

| Apple state or event | Cha-Ching access |
| --- | --- |
| `subscribed`, including an eligible free-trial period | Active |
| Auto-renew turned off, but the paid/trial period has not expired | Active until Apple's expiration date |
| `inGracePeriod` | Active through the grace-period expiration |
| `inBillingRetryPeriod` without grace | Inactive unless another Apple status independently grants access |
| `expired` | Inactive |
| `revoked` or refunded transaction | Inactive |
| Verified renewal or billing recovery | Active again |

Apple explicitly defines `subscribed` and `inGracePeriod` as entitled states and `expired`, `inBillingRetryPeriod`, and `revoked` as non-entitled when no other status grants access. Canceling auto-renew does not normally cancel the already-paid period; service continues until expiration. [Apple: renewal states](https://developer.apple.com/documentation/storekit/product/subscriptioninfo/renewalstate) [Apple: billing lifecycle](https://developer.apple.com/documentation/storekit/handling-subscriptions-billing) [Apple: notification types](https://developer.apple.com/documentation/appstoreservernotifications/notificationtype)

The implementation plan should require all of the following:

1. Pass a stable, opaque UUID through StoreKit's `appAccountToken` purchase option so signed Apple transactions can be associated with the Cha-Ching user without relying on email. Apple returns this UUID in transaction and renewal data. [Apple: app account token](https://developer.apple.com/documentation/appstoreserverapi/appaccounttoken)
2. Verify signed StoreKit transactions, consume `Transaction.updates` from app launch, finish delivered transactions, and use `Transaction.currentEntitlements` for current device presentation. [Apple: transactions](https://developer.apple.com/documentation/storekit/transaction) [Apple: transaction updates](https://developer.apple.com/documentation/storekit/transaction/updates) [Apple: current entitlements](https://developer.apple.com/documentation/storekit/transaction/currententitlements)
3. Configure an HTTPS **App Store Server Notifications V2** production endpoint and a sandbox endpoint. V1 is deprecated. Verify the signed payload, deduplicate events, update server entitlements, and return the documented HTTP status. [Apple: enable notifications](https://developer.apple.com/documentation/appstoreservernotifications/enabling-app-store-server-notifications) [Apple: notification responses and retries](https://developer.apple.com/documentation/appstoreservernotifications/responding-to-app-store-server-notifications)
4. Reconcile after missed or ambiguous events with the App Store Server API's subscription-status endpoint; notifications are prompts to refresh state, not an infallible ledger. [Apple: Get All Subscription Statuses](https://developer.apple.com/documentation/appstoreserverapi/get-all-subscription-statuses)
5. Decide whether to enable Billing Grace Period. For a supportable launch, the research recommendation is to enable it for production and sandbox, grant service during grace, and test recovery/expiry. Apple offers app-wide 3-, 16-, or 28-day settings; the exact duration and whether it covers free-to-paid renewal should be settled with the billing cadence. [Apple: Billing Grace Period](https://developer.apple.com/help/app-store-connect/manage-subscriptions/enable-billing-grace-period-for-auto-renewable-subscriptions)

## Restore, cancellation, and account deletion

StoreKit usually keeps transactions current automatically, including after reinstall. Even so, Apple requires a visible restoration mechanism. A user-triggered **Restore Purchases** action may call `AppStore.sync()`; Apple says not to call it automatically because it can prompt for App Store authentication. [Apple: `AppStore.sync()`](https://developer.apple.com/documentation/storekit/appstore/sync%28%29)

Settings should show the current subscription and an easy **Manage Subscription** action using Apple's management sheet. That sheet lets the customer view, change, or cancel. Cancellation of renewal is different from deleting the Cha-Ching account. [Apple: manage subscriptions](https://developer.apple.com/documentation/storekit/appstore/showmanagesubscriptions%28in%3A%29)

Because Cha-Ching creates accounts, an email-only deletion request is not sufficient. The app must let every user initiate full account deletion in-app, make the control easy to find, and delete the account and associated personal data unless retention is legally required. Deactivation alone is insufficient. If deletion is not immediate, the user needs a timeframe and completion notice. [Apple: offering account deletion](https://developer.apple.com/support/offering-account-deletion-in-your-app/) [Apple: App Review Guideline 5.1.1(v)](https://developer.apple.com/app-store/review/guidelines/)

The deletion flow must explain that deleting Cha-Ching does not itself cancel Apple billing, provide the Apple subscription-management sheet/link before confirmation, and still offer immediate deletion. On deletion, Cha-Ching should revoke Sign in with Apple tokens, invalidate sessions and device tokens, remove provider authorizations/secrets and custom webhook URLs, and remove the user's retained payment history according to the published retention policy. Apple specifically expects Sign in with Apple token revocation. [Apple: Sign in with Apple deletion/token revocation](https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple)

## Privacy and external payment-source connections

Cha-Ching collects data off-device as part of its primary functionality, so it cannot claim that no data is collected. The launch requires:

- a publicly accessible Privacy Policy URL in App Store Connect and an easily accessible link inside the app;
- a policy that identifies collected data, collection methods, every use and sharing partner, retention/deletion rules, and how consent or deletion can be requested;
- App Privacy answers covering Cha-Ching and every embedded third-party SDK/service, kept current as behavior changes;
- a valid privacy-manifest and required-reason API/third-party SDK audit for the submitted binary.

Apple defines collection as off-device transmission retained beyond servicing a request in real time, even when the purpose is only app functionality. [Apple: manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy) [Apple: privacy label definitions](https://developer.apple.com/app-store/app-privacy-details/) [Apple: privacy manifests](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk)

The final Privacy Nutrition Label must follow an actual production data inventory. Based on current documented behavior, likely categories requiring an explicit decision include **Email Address**, **User ID**, **Purchase History**, possibly **Other Financial Info**, and any stored buyer location; notification device tokens, IP use, analytics, diagnostics, and support data must be classified from the exact implementation. Most of these are likely linked to the signed-in Cha-Ching account and used for App Functionality. Card or bank credentials are not “Payment Info” collected by Cha-Ching if they are entered only on the provider's page and Cha-Ching never receives them. Apple nevertheless treats the payment-event data Cha-Ching deliberately ingests as collected data that must be assessed. [Apple: App Privacy data types](https://developer.apple.com/app-store/app-privacy-details/)

Connecting an existing Stripe account is not, by itself, an external purchase of Cha-Ching. No StoreKit external-purchase entitlement is needed if the provider authorization is strictly for reading seller-authorized events. The product and review notes must keep the boundary obvious:

- Stripe authorization is for an account the user already owns;
- custom webhook setup accepts events from infrastructure the user authorizes;
- neither integration pays for Cha-Ching or unlocks its subscription;
- the app does not initiate customer charges, move funds, show card entry, or provide refunds;
- Cha-Ching's own subscription is offered only through StoreKit.

This is an interpretation of Apple's purchase and financial-services rules, not a guarantee of review outcome. To reduce the risk that Apple categorizes Cha-Ching as “money management” under Guideline 3.2.1(viii) or a highly regulated financial service under Guideline 5.1.1(ix), v1 scope and metadata should consistently describe **read-only payment notifications**, and the submitting Apple Developer account should be a legal entity. If the product later initiates or manages payments, legal/licensing and App Review classification must be revisited. [Apple: App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)

There is a second material review risk: Guideline 4.10 says apps may not monetize operating-system capabilities such as Push Notifications. Cha-Ching therefore must not sell “access to push notifications,” charge per notification, or make the system notification toggle itself the paid item. The subscription must sell the ongoing SaaS service—secure provider connections, payment ingestion, normalization, retained payment feed, configuration, and cloud processing across devices—with push delivery as one output of that service. This is a risk-reduction interpretation, not an Apple safe harbor; App Review could still read a notification-first paywall or metadata as monetizing push. The paywall, App Store description, review notes, and feature gating need a consistency review against this boundary before submission. [Apple: App Review Guideline 4.10](https://developer.apple.com/app-store/review/guidelines/)

## App Review package

Apple requires production backends to be live and reviewers to receive full access, an active non-expiring demo account or fully featured demo mode, and any special resources needed to exercise account-based features. In-App Purchases must be visible and functional. [Apple: App Review Guideline 2.1](https://developer.apple.com/app-store/review/guidelines/) [Apple: platform review information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information)

The Cha-Ching review package should therefore include:

- a reachable production Worker and legal/support URLs with no placeholder content;
- reviewer contact name, email, and phone;
- exact steps to sign in, see the paywall, start the sandbox trial, restore, manage/cancel, and delete the account;
- exact steps and usable resources to evaluate Stripe and custom webhook behavior, or a review-safe fully featured demo path plus a short attached video for any external environment that is hard to reproduce;
- a plain-language note that Stripe/custom webhooks connect existing seller-owned data sources and are not payment methods for Cha-Ching;
- the subscription product identifier, included benefits, seven-day introductory offer, and where the reviewer finds the purchase and management UI;
- permission/notification instructions and a way to produce a payment/test notification without waiting for a real customer purchase.

The Support URL is required and must lead to real contact information. The Privacy Policy URL is required. Terms of Use can use Apple's standard EULA or a custom EULA, but the subscription screen still needs visible Terms and Privacy links. [Apple: platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information) [Apple: app information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information)

## Minimum pre-submission test matrix

Use StoreKit Testing in Xcode for repeatable automated/local cases, Apple's sandbox for App Store-signed transactions and server integration, and TestFlight for the final signed build. TestFlight In-App Purchases use sandbox, cost testers nothing, and do not carry into production. [Apple: In-App Purchase testing](https://developer.apple.com/in-app-purchase/) [Apple: testing stages](https://developer.apple.com/documentation/storekit/testing-at-all-stages-of-development-with-xcode-and-the-sandbox)

The launch gate should cover at least:

- eligible seven-day trial and ineligible returning customer;
- purchase success, user cancellation, pending/deferred, failure, and interrupted purchase;
- renewal and renewal with auto-renew disabled;
- restore after reinstall and on a second device;
- billing retry with and without grace, grace recovery, and grace expiry;
- refund and revocation;
- App Store Server Notification V2 signature verification, deduplication, retry, test notification, and missed-event reconciliation;
- Cha-Ching account deletion with an active subscription, Sign in with Apple token revocation, provider disconnection, and retained-data verification;
- Stripe and custom webhook integrations remaining inaccessible when the Apple-backed server entitlement is inactive;
- a full App Review walkthrough using only the information supplied to the reviewer.

## Resulting launch decisions and gates

This research resolves the Apple-policy direction but intentionally does not choose the price or standard billing cadence. The remaining plan must treat these as hard launch gates:

1. choose the standard cadence, price, grace duration, and free-to-paid grace behavior;
2. implement the StoreKit client plus server-owned Apple entitlement lifecycle;
3. implement in-app account deletion and Sign in with Apple token revocation;
4. complete the production data inventory, Privacy Policy, App Privacy answers, Terms, support page, and privacy-manifest audit;
5. establish a reviewer-access method that exercises Stripe/custom webhooks without requiring Apple to supply external provider infrastructure;
6. review the subscription value proposition and every paid gate against Guideline 4.10 so Cha-Ching sells the cloud payment-monitoring service rather than Apple's Push Notifications capability;
7. verify the Apple Developer legal entity, Paid Apps Agreement, banking, and tax status;
8. submit the first subscription, subscription group, and app version together.
