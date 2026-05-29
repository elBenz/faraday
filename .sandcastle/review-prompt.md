# TASK

Review branch `{{BRANCH}}` for issue {{TASK_ID}}: {{ISSUE_TITLE}}.

This is the explicit review point between implementation and merge.

# CONTEXT

## Branch diff

!`git diff {{TARGET_BRANCH}}...{{BRANCH}}`

## Commits on this branch

!`git log {{TARGET_BRANCH}}..{{BRANCH}} --oneline`

## Issue

!`bd show {{TASK_ID}}`

# REVIEW CHECKLIST

Check the implementation for:

- Correctness against the issue acceptance criteria
- Test coverage for changed behavior
- Clear separation of BLE scanning, RSSI classification, session state, enforcement, calibration, and persistence concerns where applicable
- Local-first behavior: no cloud, no accounts, no iOS app
- Safety: automated tests must never lock the developer Mac; enforcement must be mocked in tests
- Maintainability: clear names, minimal coupling, no needless abstractions
- Repository rules in `AGENTS.md`

# EXECUTION

If you find problems:

1. Fix them directly on `{{BRANCH}}`
2. Run `npm run typecheck` and `npm run test`
3. Commit the review fixes with a concise `RALPH:` commit message

If the branch is already acceptable, make no changes.

Do not close the issue. The merge phase closes it after a successful merge.

End with a short review summary and output <promise>COMPLETE</promise>.
