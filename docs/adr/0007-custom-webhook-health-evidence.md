# ADR 0007: Custom webhook health uses observed evidence

## Status

Accepted

## Context

A custom webhook URL can remain enabled in Cha-Ching after its external sender is removed or redeployed without forwarding logic. Cha-Ching cannot probe an arbitrary sender, and the absence of payments alone cannot prove a broken connection: a healthy store may simply have no sales.

Showing every enabled source as **Active** hides useful evidence. Declaring a source **Inactive** after an arbitrary timeout would create false certainty.

## Decision

Keep configuration status and webhook health as separate concepts.

For every known custom source, retain only bounded operational evidence: the last request time and disposition, a safe rejection message, and the last accepted-payment time. Do not retain active raw payloads.

Classify a rejected latest request as **Needs checking**. Classify silence as **Needs checking** only after at least three retained payments establish a cadence and no request arrives within three times the median recent interval, bounded to six hours through seven days. Otherwise report **Waiting for events** or **Receiving events** from direct evidence.

Run the classifier hourly. Send one source-routed APNs warning per uninterrupted warning state, and reset that latch when a later accepted or duplicate request arrives. UI copy must say that quiet activity does not prove disconnection.

The authenticated source-detail request reloads this stored evidence when source management opens. Active-source management presents the evidence passively and offers no check, refresh, reconnect, or repair action: Cha-Ching cannot probe an arbitrary external sender, and reloading its own API is not a meaningful user action. Rejected evidence directs the user to correct and resend the sender payload. Quiet evidence says that silence may be normal and is not proof of disconnection.

## Consequences

- Users can see when “enabled” no longer matches observed sender activity.
- Mapping failures produce actionable, payload-safe detail.
- Low-volume and new sources avoid unsupported outage claims.
- The client distinguishes API availability from webhook activity, never claims to probe an external sender, and does not ask the user to refresh receiver-side evidence manually.
- Detection latency is bounded by the hourly schedule plus the learned activity window.
- Migration `0012` is required before the Worker code is deployed.
