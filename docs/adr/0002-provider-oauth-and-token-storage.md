# ADR-0002: Provider OAuth and encrypted token storage

- Status: Accepted
- Date: 2026-08-11

## Context

Pasted API keys create poor revocation, excessive permissions, and a risk of secrets persisting on the device. Stripe and PayPal expose hosted authorization flows suitable for account linking.

## Decision

Use Stripe Connect OAuth and Log in with PayPal. Keep OAuth exchange and token use inside the Worker. Encrypt provider tokens with versioned AES-256-GCM ciphertext before D1 storage. Store only a SHA-256 hash of short-lived OAuth state.

## Consequences

- Provider application setup and callback registration are release prerequisites.
- Token encryption key rotation requires a version-aware migration path.
- PayPal live availability depends on external app approval.
- Connecting an account does not itself provide webhook ingestion or APNs delivery.
