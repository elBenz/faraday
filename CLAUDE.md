# Project Instructions for AI Agents

This file provides instructions and context for AI coding agents working on this project.

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


## Agent skills

### Issue tracker

Issues are tracked with GitHub Issues. See `docs/agents/issue-tracker.md`.

### Triage labels

Triage roles use the default five-label vocabulary. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context repo: read root `CONTEXT.md` if present and ADRs under `docs/adr/`. See `docs/agents/domain.md`.

## Build & Test

_Add your build and test commands here_

```bash
# Example:
# npm install
# npm test
```

## Architecture Overview

_Add a brief overview of your project architecture_

## Conventions & Patterns

_Add your project-specific conventions here_
