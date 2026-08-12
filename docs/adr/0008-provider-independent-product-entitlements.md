# ADR 0008: Provider-independent product entitlements

- Status: Accepted
- Date: 2026-08-11

## Context

Cha-Ching launches with an Apple auto-renewing subscription, but product access must remain portable to future web, Android, Shopify, and other clients. StoreKit state on one device is not a safe authorization source, and existing provider feature entitlements describe capabilities rather than the customer's commercial access.

## Decision

Cha-Ching translates verified billing-provider state into a provider-independent, server-owned product entitlement in D1. The launch product is one $14.99/year Apple subscription with a seven-day introductory trial, no monthly plan, Family Sharing, Billing Grace Period, or manual exceptions.

Apple transactions are associated with one authenticated Cha-Ching user through a stable `appAccountToken`. Purchase and restore submit signed transaction data to the Worker. The Worker verifies Apple data and records the product, transaction identity, expiration, revocation, and verification time. App Store Server Notifications V2 use the same reconciliation path. Apple-specific lifecycle values stay inside the subscription adapter.

Production and sandbox deployments accept only Apple Production and Sandbox signed data. Apple's server library intentionally does not signature-verify Xcode transactions, so the Worker decodes them only when both its configured public origin and the incoming request are loopback development. The local-only transaction identifiers are namespaced by `appAccountToken` to preserve the production uniqueness constraints across isolated Simulator accounts. Staging, production, and every non-loopback request reject that path. Production enforcement is a staged runtime policy: subscription endpoints ship first with enforcement disabled, the matching TestFlight client completes a signed sandbox purchase or restore, then enforcement may be enabled.

The public access result is only **Full access** or **Subscription required**, plus a customer-facing action. Effective feature access requires both current product access and the relevant feature entitlement. Access ends at the last verified expiration or immediately on a verified refund or revocation. Events arriving while access is off are ignored without backfill.

Deleting an account deletes its entitlement data but does not cancel Apple billing. Before deletion confirmation, the app explains that billing continues separately and offers Apple's subscription-management action.

## Consequences

- D1, not StoreKit or presentation state, is the authorization source of truth.
- Every client and ingestion path shares the same product-access policy.
- Apple verification and lifecycle complexity remains localized to one backend module.
- Future billing providers can update the same provider-independent entitlement without changing feature authorization or customer-visible states.
- A temporary Apple outage cannot extend access beyond the last verified expiration.
