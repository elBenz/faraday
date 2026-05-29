# ISSUES

Here are the ready issues in the repo:

<issues-json>

!`bd ready --json`

</issues-json>

The list above has already been filtered to issues ready for work.

# TASK

Analyze the ready issues and choose the **single next issue** to work on.

Build a dependency/overlap graph before choosing. Treat an issue B as blocked by issue A if:

- B requires code or infrastructure that A introduces
- B and A modify overlapping files or modules, making task order important
- B depends on a decision or API shape that A will establish

Selection rules:

1. Prefer an issue with zero blocking dependencies on other open issues.
2. If several are unblocked, choose the highest-priority issue.
3. If priority ties, choose the smallest coherent tracer-bullet slice.
4. If every issue is blocked, choose the single highest-priority candidate with the fewest/weakest dependencies.

Assign a branch name using the format `sandcastle/issue-{id}-{slug}`.

# OUTPUT

Output your plan as a JSON object wrapped in `<plan>` tags:

<plan>
{"issues": [{"id": "42", "title": "Fix auth bug", "branch": "sandcastle/issue-42-fix-auth-bug"}]}
</plan>

Include **exactly one issue** when work is available. If there is no ready work, output:

<plan>
{"issues": []}
</plan>
