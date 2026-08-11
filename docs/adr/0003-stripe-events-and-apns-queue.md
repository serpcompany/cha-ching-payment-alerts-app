# ADR 0003: Stripe events and APNs use D1 plus Cloudflare Queues

## Status

Accepted.

## Context

Stripe retries webhooks, APNs delivery is fallible, and an HTTP webhook response should not wait on device delivery. Cha-Ching also needs real history without persisting customer PII or provider payloads.

## Decision

- Verify Stripe signatures against the raw request body before parsing.
- Normalize supported connected-account events into D1 `sales` rows and retain only the fields the product displays or needs for idempotency.
- Use unique provider event/payment IDs for ingestion idempotency.
- Send sale IDs, not payloads or credentials, through a Cloudflare Queue.
- Track delivery state per sale/device pair in D1 and use a dead-letter queue after bounded retries.
- Sign APNs requests in the Worker with an Apple key stored as Worker secrets.
- Treat PayPal account linking and PayPal sale ingestion as separate capabilities.

## Consequences

The webhook can acknowledge after durable persistence and enqueueing, while notification retries happen independently. D1 remains the source of truth for history and delivery status. Production readiness depends on Stripe webhook configuration and signed-device APNs verification; a connected PayPal account does not produce sales until a separate PayPal webhook decision is implemented.
