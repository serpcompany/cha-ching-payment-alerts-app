# Cross-project debugging access

Cha-Ching integrations may depend on senders or infrastructure owned by other projects. Agents may use read-only commands and APIs to inspect those systems when the evidence is necessary to debug Cha-Ching.

Allowed read-only work includes:

- reading source, configuration, logs, traces, request metadata, deployment history, and status;
- querying Cloudflare observability, Worker metadata, D1 data, Queue status, and related resources without changing them; and
- correlating events across projects while avoiding disclosure of webhook URLs, tokens, payload contents, credentials, or unrelated customer data.

The following actions are forbidden outside this repository:

- editing or committing code or configuration;
- writing, deleting, replaying, or repairing application data;
- deploying, rolling back, or changing traffic;
- changing Cloudflare Workers, Pages, Queues, D1, KV, R2, secrets, routes, domains, settings, or other infrastructure; and
- invoking endpoints or commands that create or mutate production state.

If the verified fix belongs to another project or requires a Cloudflare mutation outside Cha-Ching, stop after diagnosis and report the exact required change. Do not implement or deploy it without new, explicit authorization that names the external target and action.
