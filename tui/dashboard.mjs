#!/usr/bin/env bun
import readline from "node:readline";
import { rpc, socketPath } from "./rpc.mjs";
import { check, formatCheck, setup, stop, remove, startLaunchAgent } from "./ops.mjs";

const isTTY = process.stdout.isTTY;
const c = { reset:"\x1b[0m", bold:"\x1b[1m", dim:"\x1b[2m", red:"\x1b[31m", green:"\x1b[32m", yellow:"\x1b[33m", blue:"\x1b[34m", magenta:"\x1b[35m", cyan:"\x1b[36m", gray:"\x1b[90m", inv:"\x1b[7m" };
const paint = (s, code) => isTTY ? `${code}${s}${c.reset}` : s;
const strip = (s) => String(s).replace(/\x1b\[[0-9;]*m/g, "");

let screen = "home";
let selected = 0;
let message = "";
let status = null;
let launchCheck = null;
let events = [];
let commandMode = false;
let command = "";
let pendingConfirm = null;
let afterIndex = -1;
let candidates = [];
let calibration = { phase: "idle", forbidden: [], acceptableSets: [[]], acceptableIndex: 0, live: [], summary: null };

function terminalRows() {
  return process.stdout.rows || 30;
}

const cards = {
  home: [
    ["Setup", "Build/install/start", async () => { message = formatCheck(await setup()); }],
    ["Check", "Status + fixes", async () => { screen = "check"; message = formatCheck(await check()); }],
    ["Session", "Focus controls", () => { screen = "session"; selected = 0; }],
    ["Beacon", "Scan/calibrate", () => { screen = "beacon"; selected = 0; }],
    ["Logs", "Recent events", () => { screen = "logs"; selected = 0; }],
    ["Stop", "Unload daemon", async () => { message = formatCheck(await stop()); }],
    ["Remove", "Uninstall, keep data", () => { pendingConfirm = { title: "Remove Faraday?", detail: "Uninstall LaunchAgent and binaries; keep ~/.faraday data.", run: async () => { message = formatCheck(await remove({ yes: true })); } }; }],
    ["Advanced", "Dev commands", () => { screen = "advanced"; selected = 0; }]
  ],
  session: [
    ["Start", "Begin strict session", () => rpc("session.start", { classification: "forbidden" })],
    ["Stop", "End session", () => rpc("session.stop")],
    ["Dry-run", "No native lock", () => rpc("enforcement.setMode", { mode: "dryRun" })],
    ["Armed", "May lock macOS", () => rpc("enforcement.setMode", { mode: "armed" })],
    ["Violation replay", "Dry-run scenario", () => rpc("simulation.replay", { scenario: "startActivationViolationDryRun" })],
    ["Back", "Home", () => { screen = "home"; selected = 0; }]
  ],
  beacon: [
    ["Scan + Select", "Use strongest beacon", async () => { await selectStrongestCandidate(); }],
    ["Forbidden", "Start/stop desk sample", () => { toggleForbiddenSample(); }],
    ["Acceptable", "Start/stop phone spot", () => { toggleAcceptableSample(); }],
    ["Add spot", "New acceptable place", () => { calibration.acceptableSets.push([]); calibration.acceptableIndex = calibration.acceptableSets.length - 1; calibration.phase = "acceptable"; message = `Sampling acceptable spot ${calibration.acceptableSets.length}.`; }],
    ["Evaluate", "Confidence check", async () => { await evaluateCalibration(); message = formatCalibration(); }],
    ["Back", "Home", () => { screen = "home"; selected = 0; }]
  ],
  logs: [["Back", "Home", () => { screen = "home"; selected = 0; }]],
  check: [["Run check", "Refresh diagnostics", async () => { message = formatCheck(await check()); }], ["Back", "Home", () => { screen = "home"; selected = 0; }]],
  advanced: [
    ["Start LaunchAgent", "Hidden op", async () => { startLaunchAgent(); message = formatCheck(await check()); }],
    ["Inject forbidden", "Simulation", () => rpc("simulation.inject", { classification: "forbidden" })],
    ["Inject acceptable", "Simulation", () => rpc("simulation.inject", { classification: "acceptable" })],
    ["Command mode", "Press : too", () => { commandMode = true; command = ""; }],
    ["Back", "Home", () => { screen = "home"; selected = 0; }]
  ]
};

function row(label, value) { return `${paint(label.padEnd(15), c.gray)} ${value ?? "n/a"}`; }
function badge(value) {
  const v = String(value ?? "n/a");
  const code = { active:c.green, acceptable:c.green, forbidden:c.red, armed:c.red, dryRun:c.yellow, missing:c.gray, uncertain:c.yellow, disconnected:c.red }[v] ?? c.cyan;
  return paint(v, code);
}
function box(title, lines) {
  const width = Math.max(title.length + 4, ...lines.map((l) => strip(l).length), 20);
  return [`╭─ ${paint(title, c.bold)} ${"─".repeat(Math.max(0, width-title.length-4))}╮`, ...lines.map((l) => `│ ${l}${" ".repeat(width-strip(l).length)} │`), `╰${"─".repeat(width+2)}╯`].join("\n");
}
function card(title, subtitle, active) {
  const w = 22;
  const t = title.slice(0, w - 2).padEnd(w - 2);
  const s = subtitle.slice(0, w - 2).padEnd(w - 2);
  const border = active ? c.cyan : c.reset;
  const marker = active ? paint("▶", c.cyan + c.bold) : " ";
  return [
    `${marker}${paint(`╭${"─".repeat(w)}╮`, border)}`,
    ` ${paint("│", border)} ${paint(t, active ? c.cyan + c.bold : c.bold)} ${paint("│", border)}`,
    ` ${paint("│", border)} ${paint(s, active ? c.cyan : c.dim)} ${paint("│", border)}`,
    ` ${paint(`╰${"─".repeat(w)}╯`, border)}`
  ].join("\n");
}
function renderCards(items) {
  const chunks = items.map((it, i) => card(it[0], it[1], i === selected).split("\n"));
  const rows = [];
  for (let i = 0; i < chunks.length; i += 3) {
    for (let line = 0; line < 4; line++) rows.push(chunks.slice(i, i + 3).map((x) => x[line]).join("  "));
    rows.push("");
  }
  return rows.join("\n");
}
function median(values) {
  if (values.length === 0) return null;
  const sorted = [...values].sort((a, b) => a - b);
  const i = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[i] : Math.round((sorted[i - 1] + sorted[i]) / 2);
}
function variance(values) {
  if (values.length < 2) return 0;
  const mean = values.reduce((s, x) => s + x, 0) / values.length;
  return values.reduce((s, x) => s + (x - mean) ** 2, 0) / values.length;
}
function sparkline(values, width = 28) {
  if (values.length === 0) return "";
  const blocks = "▁▂▃▄▅▆▇█";
  const sample = values.slice(-width);
  const min = Math.min(...sample), max = Math.max(...sample);
  if (min === max) return blocks[3].repeat(sample.length);
  return sample.map((v) => blocks[Math.max(0, Math.min(7, Math.round(((v - min) / (max - min)) * 7)))]).join("");
}
function formatCandidates(list) {
  if (list.length === 0) return "No beacon candidates seen. Check Bluetooth permission, power on the iBeacon, keep it nearby, then Scan + Select again.";
  return list.slice(0, 8).map((b, i) => `${i + 1}. ${b.uuid ?? "?"} major=${b.major ?? "?"} minor=${b.minor ?? "?"} rssi=${b.lastRSSI ?? "?"} seen=${b.seenCount ?? "?"}`).join("\n");
}
function formatCalibration() {
  const acceptable = calibration.acceptableSets.flat();
  const lines = [
    `phase=${calibration.phase}`,
    `forbidden n=${calibration.forbidden.length} median=${median(calibration.forbidden) ?? "n/a"} var=${variance(calibration.forbidden).toFixed(1)}`,
    `acceptable sets=${calibration.acceptableSets.length} n=${acceptable.length} median=${median(acceptable) ?? "n/a"} var=${variance(acceptable).toFixed(1)}`,
    `live ${sparkline(calibration.live)} ${calibration.live.at(-1) ?? ""}`
  ];
  if (calibration.summary) lines.push(`confidence=${calibration.summary.confidence} separation=${calibration.summary.separation} armed=${calibration.summary.armedEligible ? "yes" : "no"}`);
  return lines.join("\n");
}
async function refreshBeacon() {
  const r = await rpc("beacon.scanCandidates", {}, 2000);
  candidates = [...(r.candidates ?? [])].sort((a, b) => (b.lastRSSI ?? -999) - (a.lastRSSI ?? -999));
}
async function selectStrongestCandidate() {
  await refreshBeacon();
  const b = candidates[0];
  if (!b) { message = "No beacon candidates to select."; return; }
  await rpc("beacon.select", { uuid: b.uuid, major: b.major, minor: b.minor }, 2000);
  message = `Selected ${b.uuid} major=${b.major} minor=${b.minor}`;
}
function toggleForbiddenSample() {
  if (calibration.phase === "forbidden") { calibration.phase = "idle"; message = "Forbidden sample stopped."; return; }
  calibration.phase = "forbidden";
  message = "Sampling forbidden phone area. Press Forbidden again to stop.";
}
function toggleAcceptableSample() {
  if (calibration.phase === "acceptable") { calibration.phase = "idle"; message = "Acceptable sample stopped."; return; }
  calibration.phase = "acceptable";
  message = `Sampling acceptable spot ${calibration.acceptableIndex + 1}. Press Acceptable again to stop.`;
}
function redoCurrentCalibration() {
  if (calibration.phase === "forbidden") calibration.forbidden = [];
  else if (calibration.phase === "acceptable") calibration.acceptableSets[calibration.acceptableIndex] = [];
  else { calibration.forbidden = []; calibration.acceptableSets = [[]]; calibration.acceptableIndex = 0; calibration.summary = null; }
  message = "Cleared current calibration sample.";
}
async function ingestCalibrationRSSI() {
  if (screen !== "beacon" || (calibration.phase !== "forbidden" && calibration.phase !== "acceptable")) return;
  await refreshBeacon().catch(() => {});
  let rssi = candidates[0]?.lastRSSI;
  if (typeof rssi !== "number") {
    const live = await rpc("beacon.liveRSSI", {}, 800).catch(() => null);
    rssi = live?.samples?.at(-1)?.rssi;
  }
  if (typeof rssi !== "number") return;
  calibration.live = [...calibration.live, rssi].slice(-80);
  if (calibration.phase === "forbidden") calibration.forbidden.push(rssi);
  if (calibration.phase === "acceptable") calibration.acceptableSets[calibration.acceptableIndex].push(rssi);
}
async function evaluateCalibration() {
  const acceptable = calibration.acceptableSets.flat();
  if (!calibration.forbidden.length || !acceptable.length) { message = "Need forbidden and acceptable samples first."; return; }
  calibration.summary = await rpc("calibration.evaluate", { forbiddenRSSISamples: calibration.forbidden, acceptableRSSISamples: acceptable }, 2000);
}
function suggested() {
  if (!launchCheck?.checks?.find(([n]) => n === "plist")?.[1]) return "Run Setup to install Faraday.";
  if (!launchCheck?.checks?.find(([n]) => n === "launchd loaded")?.[1]) return "Run Setup or Advanced → Start LaunchAgent.";
  if (!status) return "Daemon not reachable. Run Check.";
  if (status.calibrationConfidence !== "high") return "Calibrate beacon before armed validation.";
  return "Ready for strict-session validation.";
}

async function refresh() {
  // Run launchd/process/socket check first and reuse its status RPC result.
  // Bun 1.2.2 can crash when a socket RPC is followed by spawnSync launchctl.
  try { launchCheck = await check(); status = launchCheck.status; } catch { launchCheck = null; status = null; }
  await ingestCalibrationRSSI();
  try {
    const tail = await rpc("events.tail", { afterIndex }, 700);
    if (tail.events?.length) events = [...events, ...tail.events].slice(-8);
    if (typeof tail.nextIndex === "number") afterIndex = tail.nextIndex;
  } catch {}
}

function render() {
  const items = cards[screen] ?? cards.home;
  if (selected >= items.length) selected = items.length - 1;
  const lines = [];
  lines.push(`${paint("⚡ Faraday", c.bold + c.cyan)} ${paint(screen.toUpperCase(), c.bold)}`);
  lines.push(paint(`socket ${socketPath}`, c.dim));
  lines.push("");
  lines.push(renderCards(items));
  lines.push(box("Suggested next action", [suggested()]));
  lines.push("");
  const installed = launchCheck?.checks?.find(([n]) => n === "daemon binary")?.[1] && launchCheck?.checks?.find(([n]) => n === "plist")?.[1];
  lines.push(box("Status", [
    row("Installed", installed ? paint("yes", c.green) : paint("no", c.yellow)),
    row("Daemon", status ? badge("connected") : badge("disconnected")),
    row("Session", badge(status?.sessionState)),
    row("Mode", badge(status?.enforcementMode)),
    row("Class", badge(status?.lastClassification)),
    row("Source", badge(status?.observationSource)),
    row("LaunchAgent", launchCheck?.checks?.find(([n]) => n === "launchd loaded")?.[1] ? paint("loaded", c.green) : paint("not loaded", c.yellow))
  ]));
  if (screen === "beacon") {
    lines.push("\n" + box("Beacon", [
      candidates[0] ? `strongest rssi=${candidates[0].lastRSSI} seen=${candidates[0].seenCount}` : "no candidates seen — check Bluetooth permission + beacon power",
      ...formatCalibration().split("\n").slice(0, 4)
    ]));
  }
  if (screen === "logs") lines.push("\n" + box("Recent events", events.length ? events.map((e) => `${String(e.index).padStart(4)} ${e.timestamp} ${e.kind}`) : [paint("none", c.dim)]));
  if ((process.stdout.columns || 80) < 78 || terminalRows() < 24) lines.push("\n" + paint("Terminal small: widen/tall pane for clean dashboard.", c.yellow));
  if (pendingConfirm) lines.push("\n" + box(pendingConfirm.title, [pendingConfirm.detail, paint("Press y to confirm, n/Esc to cancel.", c.yellow)]));
  const remaining = Math.max(4, terminalRows() - lines.length - 4);
  if (message) lines.push("\n" + box("Output", String(message).split("\n").slice(-Math.min(8, remaining))));
  lines.push("");
  lines.push(commandMode ? paint(`:${command}`, c.bold + c.cyan) : paint("←/→/↑/↓ navigate · Enter activate · : command · q quit", c.dim));
  if (isTTY) process.stdout.write("\x1b[?25l\x1b[2J\x1b[H");
  process.stdout.write(lines.join("\n") + "\n");
}

async function activate() {
  const item = (cards[screen] ?? cards.home)[selected];
  if (!item) return;
  try { const r = await item[2](); if (r) message = JSON.stringify(r, null, 2); else if (!message) message = `✓ ${item[0]}`; }
  catch (error) { message = `Command error: ${error.message}`; }
  await refresh(); render();
}
async function runRaw(line) {
  const [cmd, arg] = line.trim().split(/\s+/, 2);
  try {
    if (cmd === "start") await rpc("session.start", { classification: arg ?? "forbidden" });
    else if (cmd === "stop") await rpc("session.stop");
    else if (cmd === "mode") await rpc("enforcement.setMode", { mode: arg });
    else if (cmd === "inject") await rpc("simulation.inject", { classification: arg });
    else if (cmd === "replay") await rpc("simulation.replay", { scenario: arg });
    else if (cmd === "check") message = formatCheck(await check());
    else message = "Unknown command";
    if (!message) message = `✓ ${line}`;
  } catch (error) { message = `Command error: ${error.message}`; }
}

if (!isTTY) {
  await refresh();
  console.log(formatCheck(launchCheck ?? await check()));
  process.exit(0);
}
function exitCleanly(code = 0) {
  process.stdout.write("\x1b[?25h\x1b[0m\n");
  process.exit(code);
}
readline.emitKeypressEvents(process.stdin);
process.stdin.setRawMode(true);
await refresh(); render();
setInterval(async () => { if (!commandMode) { await refresh(); render(); } }, 1500);
process.on("exit", () => process.stdout.write("\x1b[?25h\x1b[0m"));
process.stdin.on("keypress", async (str, key) => {
  if (key.ctrl && key.name === "c") exitCleanly(0);
  if (pendingConfirm) {
    if (key.name === "escape" || key.name === "n") { pendingConfirm = null; message = "Cancelled."; render(); return; }
    if (key.name === "y") {
      const action = pendingConfirm;
      pendingConfirm = null;
      try { await action.run(); } catch (error) { message = `Command error: ${error.message}`; }
      await refresh(); render(); return;
    }
    render(); return;
  }
  if (commandMode) {
    if (key.name === "return") { const line = command; commandMode = false; command = ""; await runRaw(line); await refresh(); render(); return; }
    if (key.name === "escape") { commandMode = false; command = ""; render(); return; }
    if (key.name === "backspace") command = command.slice(0, -1); else if (str && !key.ctrl && !key.meta) command += str;
    render(); return;
  }
  const items = cards[screen] ?? cards.home;
  if (key.name === "q") exitCleanly(0);
  if (str === ":") { commandMode = true; command = ""; render(); return; }
  if (key.name === "return") return activate();
  if (key.name === "escape") { screen = "home"; selected = 0; render(); return; }
  if (key.name === "right") selected = Math.min(items.length - 1, selected + 1);
  if (key.name === "left") selected = Math.max(0, selected - 1);
  if (key.name === "down") selected = Math.min(items.length - 1, selected + 3);
  if (key.name === "up") selected = Math.max(0, selected - 3);
  render();
});
