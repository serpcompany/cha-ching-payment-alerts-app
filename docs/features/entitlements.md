# Entitlements

## User outcome

Cha-Ching can grant or withhold provider features per user without requiring an app release.

## Implemented connection-feature model

- `connect_stripe`
- `connect_paypal`
- `connect_custom`

All three are enabled by default when first materialized for an MVP user. D1 is the source of truth. These connection-feature entitlements are internal access controls, not the user-facing subscription state, so their presentation does not require a **Plan access** section.

## Launch subscription contract

The paid-product entitlement is decided but not yet implemented. It is separate from the connection-feature entitlements above and is billing-provider-independent. A user can use a provider only when both the paid-product entitlement and that provider's connection entitlement are active.

- One auto-renewing product at **$14.99 per year**, with no monthly launch option.
- A seven-day introductory trial unlocks the full product. Apple determines eligibility once per subscription group; deleting an account or changing devices does not reset eligibility.
- Family Sharing is disabled. A subscription is linked to one signed-in Cha-Ching user with `appAccountToken` and is not silently transferred between users.
- Purchase and restore ask Apple to purchase or synchronize, then require the backend to verify the signed transaction and reconcile the server entitlement. Client state never grants access.
- An active trial or paid period grants access. Turning off auto-renew keeps access through the verified paid expiration.
- Billing retry without a current paid period, expiration, refund, or revocation removes access until Apple verifies recovery or a new purchase. Billing Grace Period and manual entitlement exceptions are disabled.
- A temporary Apple verification failure preserves the last verified result only through its recorded expiration; it never extends access.
- Recovery restores access automatically. Events missed while access was off are not backfilled.
- The customer sees only **Full access** or **Subscription required**, with a reason-appropriate action such as starting the trial, updating billing, subscribing again, or restoring purchases.
- Deleting a Cha-Ching account deletes its data and access but does not cancel the Apple subscription. Before immediate deletion, the app briefly explains that Apple billing continues separately and provides the system subscription-management action; deletion never depends on cancellation.

The StoreKit adapter owns Apple-specific states. Product code and future clients ask the backend only whether the product entitlement is active, allowing another billing provider to be added without spreading its state model through the product.

## Acceptance criteria

- Missing default rows are created idempotently.
- Each user has at most one row per feature.
- Authorization fails server-side when the relevant row is disabled.
- Creating a custom payment source requires an enabled `connect_custom` entitlement.
- Unknown feature keys cannot be inserted through application APIs.
- Removing the Settings presentation does not weaken server-side authorization or feature-availability behavior.

The launch billing adapter, paid-product grant reconciliation, and customer subscription UI remain implementation work. Plan catalogs and an operator UI are out of scope for the MVP.
