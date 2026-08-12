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

### Triage labels

The canonical Matt Pocock skill labels are used without aliases. See `docs/agents/triage-labels.md`.

### Domain docs

This repository uses a single-context domain layout. See `docs/agents/domain.md`.

### Cross-project debugging

Read-only inspection of related projects and Cloudflare resources is permitted when needed to trace this app's integrations. See `docs/agents/debugging-access.md` for the strict mutation boundary.

## Repository rules

- Work on feature branches; do not commit directly to `main`.
- Do not change code, configuration, data, deployments, or infrastructure outside this repository. Related projects and their Cloudflare resources are read-only debugging inputs.
- Preserve provider secrets outside git. `.dev.vars` and Worker secrets are the supported locations.
- Run `pnpm check` and a Wrangler dry run from `backend/` after Worker changes.
- Regenerate the Xcode project with `xcodegen generate` after changing `project.yml`.
- Use a dedicated Simulator that this agent explicitly owns by UDID. Never install onto, control, shut down, erase, or repurpose an already-running Simulator that may belong to another agent or developer; follow `docs/development/simulator-auth.md`.
- Run an unsigned Simulator build after Swift or project changes.
- Keep the backend and unsigned iOS jobs in `.github/workflows/ci.yml` green before merging.
- Update feature docs, ADRs, and the tracking GitHub Issue when behavior or decisions change.
