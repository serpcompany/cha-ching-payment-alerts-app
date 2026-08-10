# AGENTS

This file is the repository map. Durable product and engineering knowledge belongs in `docs/`, not chat history.

## Start here

1. Read `CONTEXT.md` for product language, users, and invariants.
2. Read `ARCHITECTURE.md` before changing boundaries, persistence, authentication, or provider integrations.
3. Read `docs/features/index.md` and the feature document relevant to the task.
4. Read applicable ADRs under `docs/adr/`.
5. For tracked work, use GitHub Issues; keep the issue body and checklist current as the durable execution record.
6. Read `docs/brand.md` before changing names, visual styling, product copy, or public metadata.

## Agent skills

### Issue tracker

Issues are tracked in GitHub Issues. See `docs/agents/issue-tracker.md`.

### Domain docs

This repository uses a single-context domain layout. See `docs/agents/domain.md`.

## Repository rules

- Work on feature branches; do not commit directly to `main`.
- Preserve provider secrets outside git. `.dev.vars` and Worker secrets are the supported locations.
- Run `pnpm check` and a Wrangler dry run from `backend/` after Worker changes.
- Regenerate the Xcode project with `xcodegen generate` after changing `project.yml`.
- Run an unsigned Simulator build after Swift or project changes.
- Update feature docs, ADRs, and the tracking GitHub Issue when behavior or decisions change.
