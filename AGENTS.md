# Agent Guide

## Project

Faraday: macOS focus enforcement. Mac locks when phone-attached BLE beacon is too near during strict focus session.

Stable product baseline: `docs/PRODUCT.md`. Feature PRDs/specs: `docs/specs/`.

## Work rules

- Keep MVP local-first: no cloud, no accounts, no iOS app.
- Treat beacon as sensed object, not iPhone directly.
- Prefer testable core logic over UI polish.
- Separate BLE scanning, RSSI classification, session state machine, enforcement adapter, calibration, persistence.
- Never let automated tests lock developer Mac; mock enforcement adapter.
- Do not commit secrets, local scratch, or agent automation state.

## Implementation direction

- Target native Swift macOS app/daemon.
- Use CoreBluetooth for beacon observations.
- Use launchd for startup/keepalive later.
- Default behavior should be configurable and calibration-overridable.
- Enforcement target: weak-moment resistance, not adversarial security against local admin.

## Docs

- Keep `docs/PRODUCT.md` as the stable product baseline and product strategy. Product.md is mandatory.
- Keep `CONTEXT.md` glossary-only: domain terms, relationships, and avoid-language. Do not put feature specs or implementation plans there.
- Put feature PRDs and major-change specs under `docs/specs/`.
- Link Beads issues to durable spec files via `--spec-id`; issue bodies should stay summary + acceptance criteria, not duplicate full PRDs.
- Do not create a global `docs/PRD.md`; it becomes misleading as feature specs grow.
- Add ADRs under `docs/adr/` only for hard-to-reverse architecture decisions with real trade-offs.

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:7510c1e2 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files
- Treat Beads issues, comments, notes, and memories as public: this repo is public and Beads data is expected to be pushed. Do not write secrets, private strategy, customer data, undisclosed vulnerabilities, personal notes, or other non-public information into `bd`.

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/SYNC_CONCEPTS.md for details and anti-patterns.

## Session Completion

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
<!-- END BEADS INTEGRATION -->
