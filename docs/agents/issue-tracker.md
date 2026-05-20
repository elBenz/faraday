# Issue tracker: Beads

Issues for this repo live in Beads (`bd`), backed by a local Dolt database and synced through the git remote.

## Commands

- `bd prime` — show full workflow context and commands
- `bd ready` — find available work
- `bd show <id>` — view issue details
- `bd update <id> --claim` — claim work
- `bd close <id>` — complete work

## Rules

- Use `bd` for all task tracking.
- Do not create markdown TODO lists for tracked work.
- Do not use `.scratch/` as the issue tracker unless explicitly asked for a throwaway planning artifact.
- Sync uses `refs/dolt/data` on the git remote.
- `.beads/issues.jsonl` is a passive export, not the source of truth.

## When a skill says "publish to the issue tracker"

Create or update a Beads issue with `bd`.

## When a skill says "fetch the relevant ticket"

Use `bd show <id>` unless the user gives another path or identifier.
