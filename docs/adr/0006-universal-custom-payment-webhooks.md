# ADR-0006: Universal custom payment webhooks

- Status: Accepted
- Date: 2026-08-11

## Context

Many businesses keep useful product, plan, and attribution data outside their payment processor. Building and maintaining a bespoke Cha-Ching adapter for every store or automation platform would delay broad support. Reading formatted Slack messages would make Slack an unreliable and over-privileged dependency.

## Decision

Offer a provider-neutral custom payment source. Cha-Ching issues a durable private webhook URL and learns the sender's JSON shape from one encrypted setup sample. Call paths present in that sample **observed fields**, not every possible or available field. The user maps required and optional history fields, then uses every observed scalar field as an initially enabled notification row that can be hidden, renamed, remapped, or reordered. The user reviews the exact normalized push preview and explicitly activates the source.

Render notifications deterministically with the fixed title `Cha-ching!` and one ordered `{Display label}: {Formatted value}` line per enabled field. Never merge independent semantics into prose. Purchase type and sale event, for example, remain separate lines. Missing optional fields are omitted, and the public preview must exactly equal the APNs body.

Use the private URL as the MVP bearer secret. Store only its SHA-256 hash for incoming lookup and an AES-256-GCM encrypted copy for the authenticated owner experience. Hash the complete mapped Payment ID together with its source for idempotency; never truncate before hashing. Activation must submit the exact mapping and notification design used for the latest preview. Do not store active raw payloads; retain only the enabled, normalized notification label/value pairs with each sale. Support active and paused states independently from URL regeneration.

Slack, Zapier, Make, and other automation systems may send or fan out events, but none is part of Cha-Ching's custom-webhook architecture.

## Consequences

- Any system that can post JSON can integrate without new Cha-Ching provider code.
- The sender remains responsible for choosing a successful-payment event and the data included in its payload.
- The URL must be protected like a password. Explicit regeneration requires updating the sender.
- Field discovery makes onboarding flexible, but mappings can need repair if a sender later changes its payload shape.
- The MVP does not implement a sender-declared field catalog. A representative sample must contain every field the user needs to configure; a future catalog can distinguish fields that are available but absent from a particular event.
- Notification fields can appear on a device lock screen, so the UI warns users to disable private fields before activation.
- Custom sales are sender-reported rather than independently provider-verified.
- A future version may add optional signed-request verification without changing existing durable URLs.
