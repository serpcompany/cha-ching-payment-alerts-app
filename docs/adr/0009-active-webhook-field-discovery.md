# ADR-0009: Active webhooks discover new fields automatically

Accepted active custom-webhook payments discover previously unseen scalar paths without retaining raw payloads. Each new path becomes an available field appended with a readable label and enabled by default; its normalized value participates in the discovering payment, while earlier payments remain unchanged and later missing values are simply omitted. This keeps the durable private URL and avoids a separate recapture workflow, placing responsibility for a sensible payload shape on the sender's developer.

This supersedes ADR-0006's setup-only definition of observed fields and its requirement that the representative setup sample contain every field needed after activation. Existing field IDs still cannot be remapped to different paths.
