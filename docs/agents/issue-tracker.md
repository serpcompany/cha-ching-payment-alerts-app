# Issue tracker: GitHub

Issues and PRDs for this repo live as GitHub issues. Use the `gh` CLI for all operations.

## Conventions

- **Create an issue**: `gh issue create --title "..." --body "..."`. Use a heredoc for multi-line bodies.
- **Read an issue**: `gh issue view <number> --comments`, also fetching labels.
- **List issues**: `gh issue list --state open --json number,title,body,labels,comments` with appropriate filters.
- **Comment on an issue**: `gh issue comment <number> --body "..."`.
- **Apply or remove labels**: `gh issue edit <number> --add-label "..."` or `--remove-label "..."`.
- **Close**: `gh issue close <number> --comment "..."`.

Infer the repository from `git remote -v`; `gh` does this automatically inside the clone.

## Pull requests as a triage surface

**PRs as a request surface: no.**

GitHub shares one number space across issues and PRs. Resolve an ambiguous number with `gh pr view <number>` and fall back to `gh issue view <number>`.

## Skill operations

- When a skill says **publish to the issue tracker**, create a GitHub issue.
- When a skill says **fetch the relevant ticket**, run `gh issue view <number> --comments`.

## Wayfinding operations

- A map is one issue labelled `wayfinder:map`; its child tickets are GitHub sub-issues when available.
- Child types use `wayfinder:research`, `wayfinder:prototype`, `wayfinder:grilling`, or `wayfinder:task`.
- Use native GitHub issue dependencies for blocking relationships, with a `Blocked by: #<number>` fallback.
- The frontier is the first unassigned open child without open blockers, in map order.
- Claim work with `gh issue edit <number> --add-assignee @me`.
- Resolve work by commenting with the result, closing the child, and recording the decision pointer on the map.
