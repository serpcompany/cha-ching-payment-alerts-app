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

The authenticated source-detail request only reloads this stored evidence. Its UI action is **Check for new webhook activity**, not a connection test. A successful API response must be interpreted using the returned health status and reason: it must not show success styling while `needs_attention` remains. Rejected evidence directs the user to correct and resend the sender payload; quiet evidence says no newer request arrived and that silence is not proof of disconnection; a transition to receiving explicitly clears the warning. Paused monitoring offers no activity-check action.

## Consequences

- Users can see when “enabled” no longer matches observed sender activity.
- Mapping failures produce actionable, payload-safe detail.
- Low-volume and new sources avoid unsupported outage claims.
- The client distinguishes API availability from webhook activity and never claims to probe an external sender.
- Detection latency is bounded by the hourly schedule plus the learned activity window.
- Migration `0012` is required before the Worker code is deployed.
