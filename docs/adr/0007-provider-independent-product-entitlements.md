# ADR-0007: Provider-independent product entitlements

- Status: Accepted
- Date: 2026-08-11

## Context

Cha-Ching launches on iPhone with an Apple auto-renewing subscription, but later products may include a browser extension, Shopify app, Android app, or another client with a different billing provider. Making StoreKit state the product's authorization model would couple every client and feature check to Apple. The existing `connect_stripe`, `connect_paypal`, and `connect_custom` entitlements are feature-availability controls, not proof that a user has paid for the product.

The launch should remain deliberately simple: a user either has the product or must subscribe. Failed payment, expiration, refund, or revocation must stop access until the commercial problem is fixed.

## Decision

Model a **subscription** as the commercial relationship reported by a billing provider and an **entitlement** as Cha-Ching's provider-independent, server-owned grant of product access. Keep provider-specific lifecycle states inside billing adapters. D1 is the authorization source of truth; clients may initiate purchase or synchronization and present status, but they never grant access.

Launch one Apple auto-renewing product at **$14.99 per year** with a seven-day introductory trial and no monthly option. Apple decides introductory-offer eligibility once per subscription group. Disable Family Sharing and link the purchase to one authenticated Cha-Ching user with `appAccountToken`; do not silently transfer it to a different user.

The StoreKit adapter verifies Apple's signed transaction and reconciles the server entitlement for purchases, restores, renewals, and asynchronous lifecycle changes. An active trial or current paid period grants access. Cancellation retains access through the verified expiration. Billing retry without a current paid period, expiration, refund, and revocation remove access until Apple verifies recovery or a new purchase. Disable Billing Grace Period and manual exceptions. Do not backfill events missed while access was unavailable.

If Apple is temporarily unavailable, retain the last verified access only through its recorded expiration. Never extend access because verification failed. Recovery reconciles automatically.

Expose only **Full access** and **Subscription required** to customers, with a reason-appropriate action. Effective provider access requires both this paid-product entitlement and the provider's existing connection-feature entitlement. Deleting a Cha-Ching account deletes its data and access but does not cancel its Apple subscription. Before immediate deletion, briefly explain that Apple billing continues separately and provide the system subscription-management action; deletion never depends on cancellation.

## Consequences

- Every current and future client can ask the same backend authorization question without understanding StoreKit states.
- A future billing provider adds an adapter and reconciliation path rather than a new product-wide entitlement model.
- StoreKit purchase success alone cannot unlock the app; backend verification is required.
- A billing-provider outage can preserve already-verified access but cannot extend it past expiration.
- The simple no-grace policy can interrupt access during recoverable billing problems, by design.
- Connection-feature entitlements remain useful for product availability and rollout, but cannot bypass the paid-product entitlement.
