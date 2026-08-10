# Sale Ingestion and Pings

## Status

Planned. This feature is explicitly outside the provider-connection MVP.

## Intended outcome

Cha-Ching verifies Stripe and PayPal events, normalizes real payments into sales, deduplicates them, and sends an APNs notification to the owning user's registered devices.

## Required before this can be called live

- Provider-specific webhook registration and signature verification.
- Idempotent normalized sale persistence keyed by provider event/payment ID.
- Device-token registration and lifecycle handling.
- APNs signing, delivery, retry, and observability.
- A real history API and replacement of local-only test-ping behavior.
- Privacy and retention decisions for customer identifiers.

No sample sale may be represented as real revenue while this feature remains planned.
