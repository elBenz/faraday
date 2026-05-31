#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

const repoRoot = process.cwd();
const liveSourcePath = path.join(repoRoot, '.beads', 'issues.jsonl');
const archiveSourcePath = path.join(repoRoot, 'docs', 'archive', 'beads-issues-export.jsonl');
const sourcePath = fs.existsSync(liveSourcePath) ? liveSourcePath : archiveSourcePath;
const mapPath = path.join(repoRoot, 'docs', 'archive', 'beads-to-github-issue-map.json');
const live = process.argv.includes('--live');
const dryRun = !live;

function readIssues() {
  const text = fs.readFileSync(sourcePath, 'utf8');
  return text
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => JSON.parse(line))
    .filter((entry) => entry._type === 'issue')
    .sort((a, b) => String(a.created_at).localeCompare(String(b.created_at)) || a.id.localeCompare(b.id));
}

function runGh(args, options = {}) {
  if (dryRun) {
    console.log(`DRY gh ${args.map(shellQuote).join(' ')}`);
    return '';
  }
  return execFileSync('gh', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], ...options }).trim();
}

function shellQuote(value) {
  if (/^[a-zA-Z0-9_.,:/=@+-]+$/.test(value)) return value;
  return `'${value.replaceAll("'", "'\\''")}'`;
}

function labelForIssue(issue) {
  const labels = new Set(issue.labels ?? []);
  labels.add('migrated-from-beads');
  if (issue.issue_type) labels.add(`type:${issue.issue_type}`);
  if (issue.priority !== undefined && issue.priority !== null) labels.add(`priority:P${issue.priority}`);
  if (issue.status === 'in_progress') labels.add('status:in-progress');
  return [...labels].sort();
}

const labelDefinitions = new Map([
  ['migrated-from-beads', ['6f42c1', 'Imported from the former Beads issue tracker']],
  ['ready-for-agent', ['0e8a16', 'Fully specified and ready for an AFK agent']],
  ['ready-for-human', ['fbca04', 'Needs human input or decision']],
  ['status:in-progress', ['1d76db', 'Work was in progress when migrated']],
  ['type:bug', ['d73a4a', 'Bug fix']],
  ['type:epic', ['5319e7', 'Epic / parent issue']],
  ['type:feature', ['a2eeef', 'Feature work']],
  ['type:task', ['c5def5', 'Task']],
  ['priority:P1', ['b60205', 'Priority 1']],
  ['priority:P2', ['d93f0b', 'Priority 2']],
  ['priority:P3', ['fbca04', 'Priority 3']],
]);

function ensureLabels(issues) {
  const needed = new Set(issues.flatMap(labelForIssue));
  for (const name of [...needed].sort()) {
    const [color = 'ededed', description = 'Migrated Beads label'] = labelDefinitions.get(name) ?? [];
    try {
      runGh(['label', 'create', name, '--color', color, '--description', description]);
    } catch (error) {
      const stderr = String(error.stderr ?? '');
      if (!stderr.includes('already exists')) throw error;
      runGh(['label', 'edit', name, '--color', color, '--description', description]);
    }
  }
}

function dependencySections(issue, issueById, idToNumber) {
  const deps = issue.dependencies ?? [];
  const parents = deps.filter((dep) => dep.type === 'parent-child').map((dep) => dep.depends_on_id);
  const blockedBy = deps.filter((dep) => dep.type === 'blocks').map((dep) => dep.depends_on_id);
  const blocks = [];
  for (const candidate of issueById.values()) {
    for (const dep of candidate.dependencies ?? []) {
      if (dep.type === 'blocks' && dep.depends_on_id === issue.id) blocks.push(candidate.id);
    }
  }

  const lines = [];
  if (parents.length || blockedBy.length || blocks.length) {
    lines.push('## Beads relationships');
    lines.push('');
    if (parents.length) {
      lines.push('Parent:');
      for (const id of parents) lines.push(`- ${formatIssueLink(id, idToNumber)}`);
      lines.push('');
    }
    if (blockedBy.length) {
      lines.push('Blocked by:');
      for (const id of blockedBy) lines.push(`- ${formatIssueLink(id, idToNumber)}`);
      lines.push('');
    }
    if (blocks.length) {
      lines.push('Blocks:');
      for (const id of blocks) lines.push(`- ${formatIssueLink(id, idToNumber)}`);
      lines.push('');
    }
  }
  return lines.join('\n');
}

function formatIssueLink(id, idToNumber) {
  const number = idToNumber.get(id);
  return number ? `\`${id}\` (#${number})` : `\`${id}\``;
}

function buildBody(issue, issueById, idToNumber) {
  const labels = (issue.labels ?? []).length ? (issue.labels ?? []).map((label) => `\`${label}\``).join(', ') : 'None';
  const spec = issue.spec_id ? `\nSpec: \`${issue.spec_id}\`` : '';
  const relationships = dependencySections(issue, issueById, idToNumber);
  return `<!-- faraday-beads-migration\nbeads-id: ${issue.id}\n-->\n\nMigrated from Beads.\n\nBeads ID: \`${issue.id}\`\nStatus at migration: \`${issue.status}\`\nPriority: \`P${issue.priority}\`\nType: \`${issue.issue_type}\`\nOwner: ${issue.owner ? `\`${issue.owner}\`` : 'None'}\nCreated: \`${issue.created_at}\`\nUpdated: \`${issue.updated_at}\`${spec}\nOriginal labels: ${labels}\n\n${relationships ? `${relationships}\n` : ''}---\n\n${issue.description ?? ''}\n`;
}

function writeTempBody(id, body) {
  const dir = fs.mkdtempSync(path.join('/tmp', 'faraday-beads-body-'));
  const file = path.join(dir, `${id}.md`);
  fs.writeFileSync(file, body);
  return file;
}

function loadExistingMap() {
  if (!fs.existsSync(mapPath)) return new Map();
  const parsed = JSON.parse(fs.readFileSync(mapPath, 'utf8'));
  return new Map(Object.entries(parsed.issues ?? {}).map(([id, data]) => [id, data.number]));
}

function saveMap(issues, idToNumber) {
  if (dryRun) return;
  fs.mkdirSync(path.dirname(mapPath), { recursive: true });
  const output = {
    migrated_at: new Date().toISOString(),
    source: path.relative(repoRoot, sourcePath),
    issues: Object.fromEntries(
      issues.map((issue) => [
        issue.id,
        {
          number: idToNumber.get(issue.id),
          url: `https://github.com/elBenz/faraday/issues/${idToNumber.get(issue.id)}`,
          title: issue.title,
          status_at_migration: issue.status,
        },
      ]),
    ),
  };
  fs.writeFileSync(mapPath, `${JSON.stringify(output, null, 2)}\n`);
}

function main() {
  const issues = readIssues();
  const issueById = new Map(issues.map((issue) => [issue.id, issue]));
  const counts = issues.reduce((acc, issue) => {
    acc[issue.status] = (acc[issue.status] ?? 0) + 1;
    return acc;
  }, {});

  console.log(`${dryRun ? 'Dry-run' : 'Live'} migration: ${issues.length} issues`, counts);
  ensureLabels(issues);

  const idToNumber = loadExistingMap();

  for (const issue of issues) {
    if (idToNumber.has(issue.id)) continue;
    const bodyFile = writeTempBody(issue.id, buildBody(issue, issueById, idToNumber));
    const args = ['issue', 'create', '--title', issue.title, '--body-file', bodyFile];
    for (const label of labelForIssue(issue)) args.push('--label', label);
    const url = runGh(args);
    const match = url.match(/\/(\d+)$/);
    if (live && !match) throw new Error(`Could not parse issue number from ${url}`);
    const number = live ? Number(match[1]) : 1000 + idToNumber.size + 1;
    idToNumber.set(issue.id, number);
    console.log(`${issue.id} -> #${number} ${issue.title}`);
    saveMap(issues.filter((candidate) => idToNumber.has(candidate.id)), idToNumber);
  }

  for (const issue of issues) {
    const number = idToNumber.get(issue.id);
    const bodyFile = writeTempBody(issue.id, buildBody(issue, issueById, idToNumber));
    runGh(['issue', 'edit', String(number), '--body-file', bodyFile]);
  }

  for (const issue of issues.filter((candidate) => candidate.status === 'closed')) {
    const number = idToNumber.get(issue.id);
    runGh(['issue', 'close', String(number), '--reason', 'completed', '--comment', `Closed during migration from Beads. Original Beads status: ${issue.status}.`]);
  }

  saveMap(issues, idToNumber);
  console.log(`Map: ${mapPath}`);
}

main();
