# ADR-0005: Read-only Stripe App for payment notifications

- Status: Accepted
- Date: 2026-08-11

## Context

The first Stripe implementation registered Cha-Ching as a Connect payment platform and requested `read_write`. Stripe's consent screen therefore allowed Cha-Ching to create payments and take other actions even though the MVP only needs successful-payment events. Connect OAuth permits `read_only` only for legacy Extension integrations, so changing the query parameter alone would not create a valid least-privilege platform flow.

## Decision

Distribute Cha-Ching as a backend-only public Stripe App using platform-key authentication and external testing before Marketplace approval. The checked-in manifest grants exactly `event_read` and `charge_read`. Installation begins from the native app with a server-generated state, returns to the Worker, and is accepted only after Stripe's `install_signature` is verified with the Stripe App signing secret.

DS Apps (`acct_1T3IiJE8IBJK847r`) owns and publishes the integration. Installed payment accounts, including the verified live SERP! account (`acct_1Rba2Z06JrOmKRCm`), remain separate customer accounts; they are never treated as Cha-Ching's platform owner.

Store the installed Stripe account ID but no Stripe access or refresh token. Before a production install is stored, use the DS Apps platform key for a read-only, one-item Charge-list probe with the installed account header. This rejects Stripe sandboxes that otherwise have the same `acct_` identifier shape as live accounts. Ingest `charge.succeeded` from the signed installed-account webhook payload without requiring a follow-up API request.

## Consequences

- Cha-Ching cannot create, update, refund, or otherwise mutate Stripe payments.
- The production Worker secret key authenticates DS Apps as the app publisher; the installed app's `charge_read` permission still limits account access, and application code makes only `GET` requests.
- Users see object-specific read permissions during installation instead of broad platform control.
- External live testing is limited to Stripe's tester program until Marketplace approval.
- The production Worker requires the app install URL, app signing secret, and webhook signing secret.
- Removing Cha-Ching's local mapping stops sale matching immediately; uninstalling the Stripe App is the provider-side revocation mechanism.
