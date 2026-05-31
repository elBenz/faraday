# Issue tracker: GitHub Issues

Issues for this repo live in GitHub Issues for `elBenz/faraday`.

## Commands

- `gh issue list --state open` — find open work
- `gh issue view <number> --comments` — view issue details
- `gh issue create --title "..." --body-file <file>` — create work
- `gh issue edit <number> --add-assignee @me --add-label status:in-progress` — claim work
- `gh issue close <number> --comment "..."` — complete work

## Rules

- Use GitHub Issues for all tracked work.
- Do not create markdown TODO lists for tracked work.
- Do not use `.scratch/` as the issue tracker unless explicitly asked for a throwaway planning artifact.
- Keep issue bodies summary + acceptance criteria; link durable specs under `docs/specs/` instead of duplicating full PRDs.
- Former Beads issues were migrated to GitHub Issues on 2026-05-31. Mapping lives in `docs/archive/beads-to-github-issue-map.json`.

## Labels

- `ready-for-agent` — fully specified, ready for an AFK agent
- `ready-for-human` — needs human input or decision
- `status:in-progress` — claimed/active work
- `type:bug`, `type:epic`, `type:feature`, `type:task`
- `priority:P1`, `priority:P2`, `priority:P3`

## When a skill says "publish to the issue tracker"

Create or update a GitHub issue with `gh issue`.

## When a skill says "fetch the relevant ticket"

Use `gh issue view <number> --comments` unless the user gives another path or identifier.
