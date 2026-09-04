# Entitlements

## User outcome

Cha-Ching grants Full access only while the backend has a current Apple-verified product entitlement. A signed-in customer without access sees Subscription required and can purchase or restore without losing their account.

## Product access

The launch offer is one Apple auto-renewing subscription at $14.99/year with a seven-day introductory trial. Apple decides trial eligibility once per subscription group. Family Sharing and Billing Grace Period are disabled.

Purchase and restore use a stable per-user `appAccountToken`. The app sends Apple's signed transaction to the Worker, the Worker verifies and reconciles it, and D1 is the authorization source of truth. StoreKit or UI state alone never grants access.

After sign-in, launch, and foreground activation, the app first asks the Worker for product access. If the Worker reports **Subscription required** but StoreKit already has a verified current entitlement for the annual product, the app automatically submits that transaction to the Worker before settling on the paywall. This automatic path never forces `AppStore.sync()` or presents an Apple account prompt.

Restore remains an explicit fallback. It first checks StoreKit's locally available verified current entitlements and submits a matching transaction to the Worker. Only when no matching entitlement is available does the explicit restore action force `AppStore.sync()` and check again. The app reports whether purchases were restored, backend access was already active, no active purchase was found for the current App Store account, or StoreKit returned an error. A StoreKit restore failure keeps access gated and includes the Apple error domain and code so signed-device beta failures can be diagnosed without treating local state as authorization.

Local Debug runs use the checked-in StoreKit catalog and automated purchase/restore coverage described in [`docs/development/storekit-testing.md`](../development/storekit-testing.md). A dedicated E2E scheme verifies local sign-in, StoreKit purchase, HTTP reconciliation, D1 persistence, and restore. The catalog is excluded from Release; the Worker accepts Xcode transactions only over its loopback-only development boundary, and local StoreKit state never replaces remote Apple signature verification.

Customer-visible states are limited to **Full access** and **Subscription required**. Before a purchase, the primary action is **Start 7-day free trial** when StoreKit confirms eligibility and **Subscribe** otherwise. The screen states that there is no charge today, the exact localized annual price Apple will charge after the trial, and the automatic-renewal/cancellation boundary. Selecting the primary action opens a separate alert that repeats those terms and presents equally explicit **Continue to Apple** and **Not now** choices before StoreKit can present Apple's protected purchase sheet. A previously purchased but inactive account receives **Subscribe again** with the same explicit annual-price confirmation. **Restore Purchases** is always separately available. Billing-retry-specific presentation remains pending renewal-state reconciliation.

Both Full access and Subscription required surfaces provide **Manage Subscription**, support, privacy, terms, sign-out, and authenticated account deletion. Deleting a Cha-Ching account does not cancel Apple billing. The deletion screen states that boundary before confirmation and links to Apple's subscription management first; deletion then removes the server entitlement without changing the App Store subscription.

Access remains active through a verified trial or paid expiration even when auto-renew is disabled. Expiration, refund, revocation, or billing retry without a current paid period turns access off. Verified recovery turns it back on. Events received while access is off are ignored and are not backfilled.

## Feature access

- `connect_stripe`
- `connect_paypal`
- `connect_custom`

All three are enabled by default when first materialized for an MVP user. Effective feature access requires both Full access and the relevant feature entitlement.

## Acceptance criteria

- Missing default rows are created idempotently.
- Each user has at most one row per feature.
- Authorization fails server-side when the relevant row is disabled.
- Creating a custom payment source requires an enabled `connect_custom` entitlement.
- Unknown feature keys cannot be inserted through application APIs.
- A valid signed transaction for the authenticated user's token grants Full access only until its verified expiration.
- A transaction belonging to another user, product, or app is rejected.
- Refund and revocation notifications remove access; stale notifications cannot overwrite newer state.
- Stripe and custom-source events received without product access create no payment or notification and are not replayed after recovery.
- Purchase success on the device does not grant access unless backend reconciliation returns Full access.
- Starting a purchase requires explicit in-app confirmation of the annual price and renewal terms before Apple's purchase sheet opens.
- A locally available current entitlement is reconciled automatically after the backend reports Subscription required, without forcing App Store sync.
- Restore is explicit and available from both Subscription required and Settings.
- Restore always presents a visible outcome instead of silently retaining the existing access state.
- A subscription-gated user can still manage billing and delete their account without product access.
- Production enforcement is enabled through `PRODUCT_ACCESS_ENFORCEMENT` after TestFlight build 23 reconciled an Apple-signed sandbox transaction through the production Worker into D1 and loaded the Full access API set. A current backend-verified product entitlement is now required for protected APIs and incoming payment events.

Plan catalogs, manual exceptions, and an operator UI are not part of the MVP.
