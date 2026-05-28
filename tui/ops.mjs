import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawn, spawnSync } from "node:child_process";
import readline from "node:readline/promises";
import { stdin as input, stdout as output } from "node:process";
import { rpc, socketPath } from "./rpc.mjs";

export const label = "works.earendil.faraday.agent";
export const home = os.homedir();
export const faradayDir = path.join(home, ".faraday");
export const binDir = path.join(faradayDir, "bin");
export const daemonPath = path.join(binDir, "FaradayDaemon");
export const helperPath = path.join(binDir, "FaradayOverlayHelper");
export const plistPath = path.join(home, "Library", "LaunchAgents", `${label}.plist`);

const guiTarget = `gui/${process.getuid()}`;
const serviceTarget = `${guiTarget}/${label}`;

export function repoRoot() {
  return path.resolve(path.dirname(new URL(import.meta.url).pathname), "..");
}

function run(cmd, args, opts = {}) {
  const result = spawnSync(cmd, args, { cwd: repoRoot(), encoding: "utf8", ...opts });
  return { ok: result.status === 0, status: result.status, stdout: result.stdout ?? "", stderr: result.stderr ?? "" };
}

function must(cmd, args, message) {
  const result = run(cmd, args, { stdio: "pipe" });
  if (!result.ok) throw new Error(`${message}\n${result.stdout}${result.stderr}`.trim());
  return result;
}

function sleep(seconds) {
  spawnSync("/bin/sleep", [String(seconds)]);
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export async function confirm(message, assumeYes = false) {
  if (assumeYes) return true;
  const rl = readline.createInterface({ input, output });
  const answer = await rl.question(`${message}\nContinue? [y/N] `);
  rl.close();
  return /^y(es)?$/i.test(answer.trim());
}

export function writePlist() {
  fs.mkdirSync(path.dirname(plistPath), { recursive: true });
  const xml = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${label}</string>
  <key>ProgramArguments</key>
  <array><string>${daemonPath}</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>${path.join(faradayDir, "daemon.out.log")}</string>
  <key>StandardErrorPath</key><string>${path.join(faradayDir, "daemon.err.log")}</string>
</dict>
</plist>
`;
  fs.writeFileSync(plistPath, xml);
}

export function launchctl(args) {
  return run("/bin/launchctl", args);
}

export function isLoaded() {
  return launchctl(["print", serviceTarget]).ok;
}

export function build() {
  console.log("• Building Swift package");
  must("swift", ["build"], "swift build failed");
}

export function installBinaries() {
  console.log(`• Installing binaries to ${binDir}`);
  fs.mkdirSync(binDir, { recursive: true });
  fs.copyFileSync(path.join(repoRoot(), ".build", "debug", "FaradayDaemon"), daemonPath);
  fs.copyFileSync(path.join(repoRoot(), ".build", "debug", "FaradayOverlayHelper"), helperPath);
  fs.chmodSync(daemonPath, 0o755);
  fs.chmodSync(helperPath, 0o755);
}

export function startLaunchAgent() {
  if (isLoaded()) launchctl(["bootout", serviceTarget]);
  // Re-enable before bootstrap so `./faraday setup` recovers cleanly after `./faraday stop`.
  launchctl(["enable", serviceTarget]);
  const boot = launchctl(["bootstrap", guiTarget, plistPath]);
  if (!boot.ok && !boot.stderr.includes("already bootstrapped")) throw new Error(`launchctl bootstrap failed\n${boot.stdout}${boot.stderr}`.trim());
  launchctl(["enable", serviceTarget]);
  const kick = launchctl(["kickstart", "-k", serviceTarget]);
  if (!kick.ok) throw new Error(`launchctl kickstart failed\n${kick.stdout}${kick.stderr}`.trim());
}

export function stopLaunchAgent() {
  launchctl(["disable", serviceTarget]);
  launchctl(["bootout", serviceTarget]);
}

export async function setup({ yes = false } = {}) {
  const ok = await confirm(`Faraday will install a user LaunchAgent that starts at login and restarts if it exits.
Faraday can show overlays. It can lock macOS only when you explicitly switch to armed mode.

Stop temporarily: ./faraday stop
Remove completely: ./faraday remove`, yes);
  if (!ok) return { ok: false, message: "setup cancelled" };
  build();
  installBinaries();
  console.log("• Writing LaunchAgent plist");
  fs.mkdirSync(faradayDir, { recursive: true });
  writePlist();
  console.log("• Loading LaunchAgent");
  startLaunchAgent();
  // Give launchd a moment to create the Unix socket. Avoid aggressive socket polling here;
  // Bun 1.2.2 can crash when repeatedly connecting during launchd restart churn.
  sleep(2);
  return check();
}

export function stop() {
  stopLaunchAgent();
  return check();
}

export async function remove({ purge = false, yes = false } = {}) {
  stopLaunchAgent();
  if (fs.existsSync(plistPath)) fs.rmSync(plistPath);
  if (fs.existsSync(binDir)) fs.rmSync(binDir, { recursive: true, force: true });
  if (purge) {
    const ok = await confirm(`This deletes Faraday data, settings, calibration, logs, and binaries under ${faradayDir}.`, yes);
    if (ok && fs.existsSync(faradayDir)) fs.rmSync(faradayDir, { recursive: true, force: true });
  }
  return check();
}

export async function waitForRpc(timeoutMs = 3000) {
  const start = Date.now();
  let last;
  while (Date.now() - start < timeoutMs) {
    try { return await rpc("faraday.status", {}, 800); } catch (error) { last = error; }
    await new Promise((r) => setTimeout(r, 250));
  }
  throw last ?? new Error("RPC unavailable");
}

export async function check() {
  const checks = [];
  const plist = fs.existsSync(plistPath);
  const daemon = fs.existsSync(daemonPath);
  const helper = fs.existsSync(helperPath);
  const loaded = isLoaded();
  const print = launchctl(["print", serviceTarget]);
  const pidMatch = print.stdout.match(/pid = (\d+)/) ?? print.stderr.match(/pid = (\d+)/);
  let rpcStatus = null;
  let rpcError = null;
  try { rpcStatus = await rpc("faraday.status", {}, 1000); } catch (error) { rpcError = error; }

  checks.push(["plist", plist, plistPath]);
  checks.push(["daemon binary", daemon, daemonPath]);
  checks.push(["overlay helper", helper, helperPath]);
  checks.push(["launchd loaded", loaded, serviceTarget]);
  checks.push(["daemon pid", Boolean(pidMatch), pidMatch?.[1] ?? "not running"]);
  checks.push(["socket RPC", Boolean(rpcStatus), rpcStatus ? socketPath : rpcError?.message]);

  const fixes = [];
  if (!plist || !daemon || !helper) fixes.push("Run ./faraday setup");
  else if (!loaded) fixes.push("Run ./faraday start");
  else if (!rpcStatus) fixes.push("Run ./faraday restart, then ./faraday check");

  return { ok: checks.every(([, ok]) => ok), checks, status: rpcStatus, fixes };
}

export async function smoke({ cleanup = false, overlay = false } = {}) {
  const before = await check();
  console.log(formatCheck(before));
  console.log("• Restarting LaunchAgent for KeepAlive smoke");
  startLaunchAgent();
  await delay(3000);
  if (overlay) {
    console.log("• Triggering dry-run overlay replay");
    // Run replay in a short child process. Bun 1.2.2 can crash if this long-lived
    // ops process connects to the daemon during launchd restart churn.
    run(process.execPath, ["-e", "import('./tui/rpc.mjs').then(async ({rpc}) => { await rpc('simulation.replay', { scenario: 'startActivationViolationDryRun' }, 2000); await rpc('session.stop', {}, 2000).catch(() => {}); })"]);
    run("/usr/bin/pkill", ["-f", "FaradayOverlayHelper"]);
  } else {
    console.log("• Overlay replay skipped (use ./faraday smoke --overlay for visual test)");
  }
  const after = await check();
  if (cleanup) await remove();
  return after;
}

export function formatCheck(result) {
  const lines = [result.ok ? "✓ Faraday check passed" : "✗ Faraday check found issues"];
  for (const [name, ok, detail] of result.checks) lines.push(`${ok ? "✓" : "✗"} ${name}: ${detail}`);
  if (result.status) lines.push(`session=${result.status.sessionState} mode=${result.status.enforcementMode} source=${result.status.observationSource}`);
  if (result.fixes?.length) lines.push("Fix: " + [...new Set(result.fixes)].join("; "));
  return lines.join("\n");
}

export function autoStartInstalled() {
  if (fs.existsSync(plistPath) && fs.existsSync(daemonPath) && !isLoaded()) {
    startLaunchAgent();
  }
}

export function openDashboard() {
  autoStartInstalled();
  const child = spawn(process.execPath, [path.join(repoRoot(), "tui", "dashboard.mjs")], { stdio: "inherit", cwd: repoRoot() });
  child.on("exit", (code) => process.exit(code ?? 0));
}
