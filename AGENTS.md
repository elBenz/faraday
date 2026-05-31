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
- Link GitHub issues to durable spec files; issue bodies should stay summary + acceptance criteria, not duplicate full PRDs.
- Do not create a global `docs/PRD.md`; it becomes misleading as feature specs grow.
- Add ADRs under `docs/adr/` only for hard-to-reverse architecture decisions with real trade-offs.

## GitHub Issue Tracker

This project uses GitHub Issues for task tracking. See `docs/agents/issue-tracker.md`.

### Quick Reference

```bash
gh issue list --state open
gh issue view <number> --comments
gh issue edit <number> --add-assignee @me --add-label status:in-progress
gh issue close <number> --comment "..."
```

### Rules

- Use GitHub Issues for tracked work; do not create markdown TODO lists.
- Treat GitHub issues and comments as public. Do not write secrets, private strategy, customer data, undisclosed vulnerabilities, or other non-public information there.
- Former Beads issues were migrated on 2026-05-31. Mapping: `docs/archive/beads-to-github-issue-map.json`.

## Session Completion

**When ending a work session**, complete all steps below. Work is not complete until `git push` succeeds.

1. File GitHub issues for remaining work.
2. Run quality gates if code changed.
3. Update/close relevant GitHub issues.
4. Push to remote:
   ```bash
   git pull --rebase
   git push
   git status  # must show up to date with origin
   ```
5. Clean up stashes/temp branches.
6. Hand off concise context for next session.
