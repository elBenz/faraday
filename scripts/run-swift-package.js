#!/usr/bin/env node
const { spawnSync } = require('node:child_process');

const command = process.argv[2];
if (!['build', 'test'].includes(command)) {
  console.error('Usage: node scripts/run-swift-package.js <build|test>');
  process.exit(64);
}

const swiftCheck = spawnSync('swift', ['--version'], { stdio: 'ignore' });
if (swiftCheck.error && swiftCheck.error.code === 'ENOENT') {
  console.warn(`Swift toolchain not found; skipping \`swift ${command}\` in this environment.`);
  process.exit(0);
}
if (swiftCheck.status !== 0) {
  console.error('Swift toolchain check failed.');
  process.exit(swiftCheck.status || 1);
}

const result = spawnSync('swift', [command], { stdio: 'inherit' });
if (result.error) {
  console.error(result.error.message);
  process.exit(1);
}
process.exit(result.status ?? 0);
