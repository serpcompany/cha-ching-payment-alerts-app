# Drizzle declares schema; Wrangler executes D1 migrations

Status: proposed

Cha-Ching will adopt Drizzle incrementally as the TypeScript schema and query
layer while keeping Wrangler as the sole executor and ledger for local, staging,
and production D1 migrations. This avoids competing migration ledgers, preserves
the deployed SQL history, and lets schema declarations and query conversions be
reviewed separately from production promotion. Until the complete existing
schema is ported and verified, `backend/migrations/` remains the schema authority;
Drizzle-generated SQL must not be promoted or pushed directly to shared D1.

Production migration commands name the production database explicitly, require
an operator confirmation value for mutation, and precede compatible Worker
deployment and authenticated read-only smoke checks. A separate staging D1 is a
prerequisite for claiming staging rehearsal; application data is never promoted
between environments.
