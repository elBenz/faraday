# TASK

Merge the following reviewed branch into the current branch:

{{BRANCHES}}

For each branch:

1. Run `git merge <branch> --no-edit`
2. If there are merge conflicts, resolve them intelligently by reading both sides and choosing the correct resolution
3. Run `npm run typecheck` and `npm run test`
4. If tests fail, fix the issues before proceeding
5. Commit any conflict-resolution or test-fix changes if needed

# CLOSE ISSUES

After a branch merges cleanly and checks pass, close its issue:

`bd close <ID> --reason="Completed by Sandcastle"`

Issues:

{{ISSUES}}

Once you've merged everything you can, output <promise>COMPLETE</promise>.
