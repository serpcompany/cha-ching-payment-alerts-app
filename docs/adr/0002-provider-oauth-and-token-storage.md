# ADR-0002: Provider authorization and encrypted token storage

- Status: Accepted
- Date: 2026-08-11

## Context

Pasted API keys create poor revocation, excessive permissions, and a risk of secrets persisting on the device. Stripe and PayPal expose hosted authorization flows suitable for account linking.

## Decision

Use a least-privilege Stripe App and Log in with PayPal. Keep provider callbacks, OAuth exchange, and credential use inside the Worker. For Stripe, verify the signed install callback and persist only its account ID; no Stripe access token is required. Encrypt provider tokens that are still issued (including PayPal tokens) with versioned AES-256-GCM ciphertext before D1 storage. Store only a SHA-256 hash of short-lived authorization state. Stripe-specific permissions are further constrained by ADR-0005.

## Consequences

- Provider application setup and callback registration are release prerequisites.
- Token encryption key rotation requires a version-aware migration path.
- Stripe App and webhook signing secrets remain Worker secrets and are never copied into connection rows.
- PayPal live availability depends on external app approval.
- Connecting an account does not itself provide webhook ingestion or APNs delivery.
