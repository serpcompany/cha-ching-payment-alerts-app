# Domain Docs

How engineering skills consume this repository's domain documentation.

## Before exploring, read these

- `CONTEXT.md` at the repository root.
- Relevant ADRs under `docs/adr/`.

If a referenced domain document does not exist, proceed silently. Domain-modeling workflows create new documents when terms or decisions are actually resolved.

## File structure

This is a single-context repository:

```text
/
├── CONTEXT.md
├── docs/adr/
├── docs/features/
├── Sales Ping/
└── backend/
```

## Vocabulary

Use the terms defined in `CONTEXT.md` in issues, specifications, tests, and implementation. Avoid synonyms that blur the distinction between a Sales Ping user, a connected provider account, and that user's customers.

## ADR conflicts

If proposed work contradicts an accepted ADR, surface the conflict explicitly rather than silently overriding it.
