# Cha-Ching competitor research

Date checked: 2026-08-11

## Question

What does Hookfire currently offer, who is it for, how does it receive and
present events, what does it charge, and where does it meaningfully overlap
with or differ from Cha-Ching's documented v1?

## Hookfire

### Product and target customer

Hookfire presents itself as a real-time phone-notification service for events
from tools a business already uses. Its advertised scope includes payments,
customer messages, errors, deploys, and arbitrary webhook events, with a mobile
feed and event-detail views rather than payment alerts alone. Its named customer
groups are solo founders, developers, micro-SaaS teams, bootstrapped businesses,
and, more broadly, indie hackers and lean teams. Sources: [Hookfire home page](https://www.hookfire.app/)
and [Hookfire App Store listing](https://apps.apple.com/us/app/hookfire/id6760303618).

The App Store listing describes the iPhone app as a companion to
`hookfire.app`: integrations are connected on the web, while the phone receives
push notifications and provides notification history, filtering, organization
switching, and detailed event metadata. Source: [Hookfire App Store listing](https://apps.apple.com/us/app/hookfire/id6760303618).

### Inputs and notification behavior

- Hookfire's public integration directory lists 33 prebuilt sources across
  billing, developer tools, ecommerce, payments, and support. It also offers a
  custom-source path for any webhook sender. Source: [Hookfire integrations](https://www.hookfire.app/integrations).
- A Hookfire account receives unique webhook endpoints. For prebuilt sources,
  the owner creates an integration, pastes its Hookfire URL into the sending
  service, and selects which supported events should be received. Source:
  [Hookfire home page](https://www.hookfire.app/) and [Hookfire Stripe integration](https://www.hookfire.app/integrations/stripe).
- Hookfire's Stripe integration accepts nine named Stripe event types, supports
  signature verification, lets the owner select event triggers, and lets a team
  route an event to push plus history or to history only. Setup requires the
  owner to configure Hookfire as a Stripe webhook endpoint and copy the Stripe
  signing secret back into Hookfire. Source: [Hookfire Stripe integration](https://www.hookfire.app/integrations/stripe).
- A Hookfire custom source is described with YAML that declares its events,
  parses payload fields, maps notification titles and bodies, and can optionally
  configure HMAC or another signature-verification strategy. Custom sources are
  limited to the Max plan. Source: [Hookfire integrations](https://www.hookfire.app/integrations).
- Hookfire advertises instant phone delivery, rich event details, integration
  status, and a unified notification stream. Its App Store listing also states
  that the app retains a browsable notification history and supports filtering
  by source, read/saved status, or organization. Sources: [Hookfire home page](https://www.hookfire.app/)
  and [Hookfire App Store listing](https://apps.apple.com/us/app/hookfire/id6760303618).

### Public pricing

Hookfire's public page displays the following standard plans and says a
seven-day trial requires no credit card. The pricing introduction says the trial
starts on Max, while the line beneath the plan cards says every plan starts with
a seven-day trial; this note preserves both statements rather than inferring a
different trial policy. Source: [Hookfire pricing](https://www.hookfire.app/#pricing).

| Plan | Monthly cadence | Annual cadence | Displayed features |
| --- | ---: | ---: | --- |
| Pro | $9.90/month | $99/year | Up to 3 integrations, unlimited events per integration, up to 3 team members, OneSignal push notifications, and priority support |
| Max | $14.90/month | $149/year | Unlimited integrations, events, and team members; custom webhook sources; OneSignal push notifications |
| Releasy Suite | $29.90/month | $299/year | Hookfire Max plus Upvoted Max and Indie Polls Max under one bill |

All prices and feature descriptions in the table come directly from
[Hookfire pricing](https://www.hookfire.app/#pricing) as displayed on the date
checked. The App Store separately lists the companion iPhone download as free;
that listing does not enumerate these service-plan prices. Source:
[Hookfire App Store listing](https://apps.apple.com/us/app/hookfire/id6760303618).

### Comparison with Cha-Ching v1

| Area | Hookfire | Documented Cha-Ching v1 | Assessment |
| --- | --- | --- | --- |
| Customer | Explicitly targets solo founders, developers, micro-SaaS teams, and bootstrapped businesses. [Source](https://www.hookfire.app/) | Targets indie founders and small software businesses. [Source](../../CONTEXT.md) | Direct audience overlap. |
| Core outcome | Sends phone alerts for payments and other operational events and provides a notification history. [Source](https://apps.apple.com/us/app/hookfire/id6760303618) | Persists successful payments in a Payments feed and sends iPhone notifications. [Source](../features/sale-ingestion-and-notifications.md) | Direct overlap on payment awareness; Hookfire's event scope is broader. |
| Stripe input | Receives a user-configured Stripe webhook, verifies its signing secret, and supports nine event types. [Source](https://www.hookfire.app/integrations/stripe) | Uses a read-only Stripe App connection and currently ingests verified `charge.succeeded` events. [Source](../features/provider-account-connections.md) [Source](../features/sale-ingestion-and-notifications.md) | Similar user outcome, materially different connection model and event breadth. |
| Arbitrary sources | Max customers define custom sources in YAML, including events, payload parsing, title/body mapping, and optional signature verification. [Source](https://www.hookfire.app/integrations) | An owner sends a representative JSON event to a private source URL, then maps observed scalar fields and controls labels, inclusion, and ordering in the iPhone app. [Source](../features/custom-webhook-payment-sources.md) | Both support arbitrary webhooks; Hookfire is definition-driven, while Cha-Ching is sample-driven and payment-normalization-focused. |
| Delivery control | Supports per-event push-plus-record or record-only routing and team-wide recipients. [Source](https://www.hookfire.app/integrations/stripe) | Uses a per-device payment-notification preference and sends one normalized payment notification per eligible device. [Source](../features/sale-ingestion-and-notifications.md) | Hookfire exposes broader event/team routing; Cha-Ching documents a narrower personal-device control. |
| Team model | Pro includes up to 3 team members; Max includes unlimited team members. [Source](https://www.hookfire.app/#pricing) | The documented product model centers on one signed-in user and owner-scoped sources, payments, and devices. [Source](../../CONTEXT.md) [Source](../features/custom-webhook-payment-sources.md) | Hookfire is explicitly team-capable; Cha-Ching v1 is individual-owner-focused. |
| Surface | Integrations are connected on the web and monitored from a companion iPhone app. [Source](https://apps.apple.com/us/app/hookfire/id6760303618) | Provider and custom-source setup are documented as in-app flows. [Source](../features/provider-account-connections.md) [Source](../features/custom-webhook-payment-sources.md) | Cha-Ching's documented setup is more iPhone-native; Hookfire separates web configuration from mobile monitoring. |
| Custom-webhook price anchor | Custom sources require Max: $14.90/month or $149/year. [Source](https://www.hookfire.app/#pricing) | Launch is set at $14.99/year with a seven-day introductory trial and no monthly option. [Source](../features/entitlements.md) | Cha-Ching is priced far below Hookfire's broader custom-source plan; the products' different scope makes this context rather than a like-for-like value comparison. |

### Decision-relevant inferences

The following are interpretations of the first-party evidence, not claims made
by Hookfire:

- **Hookfire is a direct competitor for the “know when I made a sale” job.** Its
  positioning uses that outcome explicitly, targets substantially the same
  founder audience, supports Stripe and arbitrary webhooks, and delivers events
  to an iPhone. Evidence: [Hookfire home page](https://www.hookfire.app/),
  [Hookfire Stripe integration](https://www.hookfire.app/integrations/stripe),
  and [Hookfire integrations](https://www.hookfire.app/integrations).
- **Its product boundary is substantially broader than Cha-Ching v1.** Hookfire
  combines payment, support, development, deployment, and error events for
  teams, whereas Cha-Ching's current documentation is deliberately centered on
  normalized successful payments for an individual owner. Evidence:
  [Hookfire integrations](https://www.hookfire.app/integrations),
  [Cha-Ching context](../../CONTEXT.md), and
  [Cha-Ching payment ingestion](../features/sale-ingestion-and-notifications.md).
- **Hookfire's prices should be treated as an upper-market comparison, not as
  evidence that Cha-Ching should match them.** A price comparison must account
  for Hookfire's larger integration catalog, team seats, non-payment event
  coverage, and the fact that arbitrary custom sources require its higher Max
  plan. Evidence: [Hookfire pricing](https://www.hookfire.app/#pricing) and
  [Hookfire integrations](https://www.hookfire.app/integrations).
- **Cha-Ching can differentiate through focus and setup experience rather than
  integration count.** The documented sample-driven custom notification editor,
  direct Stripe App connection, normalized payment feed, and payment-specific
  sound/detail experience form a narrower product proposition than Hookfire's
  general webhook stream. Evidence: [Cha-Ching custom webhook sources](../features/custom-webhook-payment-sources.md),
  [Cha-Ching provider connections](../features/provider-account-connections.md),
  and [Cha-Ching payment notifications](../features/sale-ingestion-and-notifications.md).

## Scope and limitations

- This note uses only Hookfire's own public website and its developer-controlled
  App Store listing for Hookfire facts. It does not independently test the app,
  create an account, or verify paid-plan behavior.
- Pricing and features are a point-in-time snapshot and should be rechecked
  before using them in future pricing or positioning decisions.
- “Instant” and other performance language above are Hookfire's public claims;
  this research did not measure delivery latency.
- This is competitor research, not a recommendation to copy Hookfire's product,
  pricing, metadata, or implementation.
