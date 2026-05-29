// Sequential Task Reviewer — task-by-task orchestration loop
//
// This workflow processes one Beads issue at a time:
//   Phase 1 (Plan):      A planning agent chooses the single next ready issue.
//   Phase 2 (Implement): An implementer works that issue on its own branch.
//   Phase 3 (Review):    A reviewer checks the branch before merge and may
//                        commit fixes on the same branch.
//   Phase 4 (Merge):     A merger merges that one reviewed branch, runs gates,
//                        and closes the issue.
//
// The outer loop repeats up to MAX_ITERATIONS times so newly unblocked issues
// are picked up after each reviewed merge.
//
// Usage:
//   npx tsx .sandcastle/main.mts
// Or add to package.json:
//   "scripts": { "sandcastle": "npx tsx .sandcastle/main.mts" }

import * as sandcastle from "@ai-hero/sandcastle";
import { docker } from "@ai-hero/sandcastle/sandboxes/docker";

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

// Maximum number of plan→implement→review→merge cycles before stopping.
// Each cycle processes one issue.
const MAX_ITERATIONS = 10;

// Use host pi Codex subscription login inside each sandbox.
// Mount ~/.pi/agent read-only, then copy into container-local home so agents do
// not contend on pi auth/settings lock files or mutate host creds.
const PLANNER_MODEL = "openai-codex/gpt-5.5:high";
const IMPLEMENTER_MODEL = "openai-codex/gpt-5.3-codex:high";
const REVIEWER_MODEL = "openai-codex/gpt-5.5:xhigh";
const MERGER_MODEL = "openai-codex/gpt-5.5:high";

const makeSandbox = () =>
  docker({
    mounts: [
      {
        hostPath: "~/.pi/agent",
        sandboxPath: "/mnt/pi-agent",
        readonly: true,
      },
    ],
    env: {
      PI_CODING_AGENT_DIR: "/home/agent/.pi/agent",
    },
  });

// Hooks run inside the sandbox before the agent starts each iteration.
// npm install ensures the sandbox always has fresh dependencies.
const hooks = {
  sandbox: {
    onSandboxReady: [
      {
        command:
          "mkdir -p /home/agent/.pi && rm -rf /home/agent/.pi/agent && cp -R /mnt/pi-agent /home/agent/.pi/agent && chmod -R u+rwX /home/agent/.pi/agent && npm install",
      },
    ],
  },
};

// Copy node_modules from the host into the worktree before each sandbox
// starts. Avoids a full npm install from scratch; the hook above handles
// platform-specific binaries and any packages added since the last copy.
const copyToWorktree = ["node_modules"];

// ---------------------------------------------------------------------------
// Main loop
// ---------------------------------------------------------------------------

for (let iteration = 1; iteration <= MAX_ITERATIONS; iteration++) {
  console.log(`\n=== Iteration ${iteration}/${MAX_ITERATIONS} ===\n`);

  // -------------------------------------------------------------------------
  // Phase 1: Plan
  //
  // The planning agent reads ready issues, reasons about dependencies and
  // overlap, then selects exactly one next issue for this cycle.
  // -------------------------------------------------------------------------
  const plan = await sandcastle.run({
    hooks,
    sandbox: makeSandbox(),
    name: "planner",
    maxIterations: 1,
    agent: sandcastle.pi(PLANNER_MODEL),
    promptFile: "./.sandcastle/plan-prompt.md",
  });

  const planMatch = plan.stdout.match(/<plan>([\s\S]*?)<\/plan>/);
  if (!planMatch) {
    throw new Error(
      "Planning agent did not produce a <plan> tag.\n\n" + plan.stdout,
    );
  }

  const { issues } = JSON.parse(planMatch[1]!) as {
    issues: { id: string; title: string; branch: string }[];
  };

  if (issues.length === 0) {
    console.log("No ready issue to work on. Exiting.");
    break;
  }

  const issue = issues[0]!;
  if (issues.length > 1) {
    console.log(
      `Planner returned ${issues.length} issues; running only first for task-by-task mode.`,
    );
  }

  console.log("Planning complete. Next issue:");
  console.log(`  ${issue.id}: ${issue.title} → ${issue.branch}`);

  // -------------------------------------------------------------------------
  // Phase 2 + 3: Implement, then review
  //
  // A single sandbox is shared by implementer and reviewer so review fixes land
  // on the same branch before merge.
  // -------------------------------------------------------------------------
  const taskSandbox = await sandcastle.createSandbox({
    branch: issue.branch,
    sandbox: makeSandbox(),
    hooks,
    copyToWorktree,
  });

  let taskCommits: { sha: string }[] = [];

  try {
    const implement = await taskSandbox.run({
      name: "implementer",
      maxIterations: 100,
      agent: sandcastle.pi(IMPLEMENTER_MODEL),
      promptFile: "./.sandcastle/implement-prompt.md",
      promptArgs: {
        TASK_ID: issue.id,
        ISSUE_TITLE: issue.title,
        BRANCH: issue.branch,
      },
    });

    taskCommits = [...taskCommits, ...implement.commits];

    if (taskCommits.length === 0) {
      console.log("Implementation produced no commits. Skipping review and merge.");
      continue;
    }

    console.log(`\nImplementation complete on branch: ${issue.branch}`);
    console.log(`Implementation commits: ${implement.commits.length}`);

    const review = await taskSandbox.run({
      name: "reviewer",
      maxIterations: 1,
      agent: sandcastle.pi(REVIEWER_MODEL),
      promptFile: "./.sandcastle/review-prompt.md",
      promptArgs: {
        TASK_ID: issue.id,
        ISSUE_TITLE: issue.title,
        BRANCH: issue.branch,
      },
    });

    taskCommits = [...taskCommits, ...review.commits];

    console.log("\nReview complete.");
    console.log(`Review commits: ${review.commits.length}`);
  } finally {
    await taskSandbox.close();
  }

  if (taskCommits.length === 0) {
    console.log("No commits produced. Nothing to merge.");
    continue;
  }

  // -------------------------------------------------------------------------
  // Phase 4: Merge
  //
  // Merge this one reviewed branch before planning the next issue. This keeps
  // later planning grounded in current mainline state and avoids parallel drift.
  // -------------------------------------------------------------------------
  await sandcastle.run({
    hooks,
    sandbox: makeSandbox(),
    name: "merger",
    maxIterations: 1,
    agent: sandcastle.pi(MERGER_MODEL),
    promptFile: "./.sandcastle/merge-prompt.md",
    promptArgs: {
      BRANCHES: `- ${issue.branch}`,
      ISSUES: `- ${issue.id}: ${issue.title}`,
    },
  });

  console.log("\nReviewed branch merged.");
}

console.log("\nAll done.");
