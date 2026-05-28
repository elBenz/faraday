#!/usr/bin/env bun
import net from "node:net";
import readline from "node:readline";
import os from "node:os";
import path from "node:path";

const socketPath = process.env.FARADAY_SOCKET ?? path.join(os.homedir(), ".faraday", "faraday.sock");
let nextId = 1;
let afterIndex = -1;
let recentEvents = [];
let lastCommandMessage = "";
let lastRender = "";

const isTTY = process.stdout.isTTY;
const color = {
  reset: "\x1b[0m",
  bold: "\x1b[1m",
  dim: "\x1b[2m",
  red: "\x1b[31m",
  green: "\x1b[32m",
  yellow: "\x1b[33m",
  blue: "\x1b[34m",
  magenta: "\x1b[35m",
  cyan: "\x1b[36m",
  gray: "\x1b[90m"
};

function paint(text, code) {
  if (!isTTY) return text;
  return `${code}${text}${color.reset}`;
}

function badge(value, palette = {}) {
  const text = String(value ?? "n/a");
  const code = palette[text] ?? palette.default ?? color.cyan;
  return paint(text, code);
}

function row(label, value) {
  return `${paint(label.padEnd(14), color.gray)} ${value}`;
}

function box(title, lines) {
  const width = Math.max(title.length + 4, ...lines.map((line) => stripAnsi(line).length), 0);
  const top = `╭─ ${paint(title, color.bold)} ${"─".repeat(Math.max(0, width - title.length - 4))}╮`;
  const body = lines.map((line) => `│ ${line}${" ".repeat(Math.max(0, width - stripAnsi(line).length))} │`);
  const bottom = `╰${"─".repeat(width + 2)}╯`;
  return [top, ...body, bottom].join("\n");
}

function stripAnsi(text) {
  return String(text).replace(/\x1b\[[0-9;]*m/g, "");
}

const calibration = {
  active: false,
  phase: "idle", // idle|forbidden|acceptable
  forbidden: [],
  acceptableSets: [[]],
  currentAcceptableIndex: 0,
  live: []
};

function rpc(method, params = {}) {
  return new Promise((resolve, reject) => {
    const client = net.createConnection(socketPath);
    const request = JSON.stringify({ jsonrpc: "2.0", id: nextId++, method, params }) + "\n";
    let buffer = "";
    let settled = false;

    function finish(fn, value) {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      client.destroy();
      fn(value);
    }

    const timer = setTimeout(() => finish(reject, new Error(`RPC timeout for ${method}; is FaradayDaemon running?`)), 1200);

    client.on("connect", () => client.write(request));
    client.on("data", (chunk) => {
      buffer += chunk.toString("utf8");
      const idx = buffer.indexOf("\n");
      if (idx === -1) return;
      try {
        const payload = JSON.parse(buffer.slice(0, idx));
        if (payload.error) finish(reject, new Error(`${payload.error.code}: ${payload.error.message}`));
        else finish(resolve, payload.result ?? {});
      } catch (error) {
        finish(reject, error);
      }
    });
    client.on("error", (error) => finish(reject, error));
  });
}

function median(values) {
  if (values.length === 0) return null;
  const sorted = [...values].sort((a, b) => a - b);
  const i = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 1 ? sorted[i] : Math.round((sorted[i - 1] + sorted[i]) / 2);
}

function variance(values) {
  if (values.length < 2) return 0;
  const mean = values.reduce((s, x) => s + x, 0) / values.length;
  return values.reduce((s, x) => s + (x - mean) ** 2, 0) / values.length;
}

function sparkline(values, width = 24) {
  if (values.length === 0) return "";
  const blocks = "▁▂▃▄▅▆▇█";
  const sample = values.slice(-width);
  const min = Math.min(...sample);
  const max = Math.max(...sample);
  if (min === max) return blocks[3].repeat(sample.length);
  return sample.map((v) => blocks[Math.max(0, Math.min(7, Math.round(((v - min) / (max - min)) * 7)))]).join("");
}

async function ingestLiveRSSI() {
  const candidates = await rpc("beacon.scanCandidates");
  const list = candidates.candidates ?? [];
  if (list.length === 0) return null;
  const strongest = [...list].sort((a, b) => b.lastRSSI - a.lastRSSI)[0];
  return strongest.lastRSSI;
}

async function calibrationSummary() {
  if (!calibration.active || calibration.forbidden.length === 0 || calibration.acceptableSets.flat().length === 0) return null;
  const acceptable = calibration.acceptableSets.flat();
  return rpc("calibration.evaluate", {
    forbiddenRSSISamples: calibration.forbidden,
    acceptableRSSISamples: acceptable
  });
}

async function render() {
  let status;
  let tail = { events: [] };
  let launchAgent = { installed: false, loaded: false };
  let connectionError = null;

  try {
    [status, tail, launchAgent] = await Promise.all([
      rpc("faraday.status"),
      rpc("events.tail", { afterIndex }),
      rpc("launchAgent.status").catch(() => ({ installed: false, loaded: false }))
    ]);
  } catch (error) {
    connectionError = error;
    status = {
      observationSource: "offline",
      enforcementMode: "n/a",
      sessionState: "disconnected",
      lastClassification: "n/a",
      calibrationConfidence: "n/a",
      overlayState: "n/a",
      countdownSeconds: "n/a"
    };
  }

  const events = tail.events ?? [];
  if (events.length > 0) {
    recentEvents = [...recentEvents, ...events].slice(-10);
  }
  if (typeof tail.nextIndex === "number") afterIndex = tail.nextIndex;

  if (calibration.active && (calibration.phase === "forbidden" || calibration.phase === "acceptable")) {
    const live = await ingestLiveRSSI();
    if (typeof live === "number") {
      calibration.live.push(live);
      calibration.live = calibration.live.slice(-60);
      if (calibration.phase === "forbidden") calibration.forbidden.push(live);
      if (calibration.phase === "acceptable") calibration.acceptableSets[calibration.currentAcceptableIndex].push(live);
    }
  }

  const lines = [];
  lines.push(`${paint("⚡ Faraday", color.bold + color.cyan)} ${paint("Session Dashboard", color.bold)}`);
  lines.push(paint(`socket ${socketPath}`, color.dim));
  if (connectionError) {
    lines.push(paint(`daemon disconnected: ${connectionError.message}`, color.red));
    lines.push(paint("start it with: swift run FaradayDaemon", color.yellow));
  }
  lines.push("");

  lines.push(box("Status", [
    row("Source", badge(status.observationSource, { simulation: color.magenta, beacon: color.green, default: color.cyan })),
    row("Mode", badge(status.enforcementMode, { dryRun: color.yellow, armed: color.red })),
    row("Session", badge(status.sessionState, { inactive: color.gray, idle: color.gray, disconnected: color.red, active: color.green, pendingActivation: color.yellow, violated: color.red, default: color.cyan })),
    row("Classification", badge(status.lastClassification ?? "n/a", { acceptable: color.green, forbidden: color.red, uncertain: color.yellow, missing: color.gray })),
    row("Calibration", badge(status.calibrationConfidence ?? "n/a", { high: color.green, medium: color.yellow, low: color.red, default: color.gray })),
    row("Overlay", badge(status.overlayState ?? "n/a", { hidden: color.gray, showingViolation: color.red, showingDegradedBeaconTrust: color.yellow })),
    row("Countdown", badge(status.countdownSeconds ?? "n/a", { default: color.yellow })),
    row("LaunchAgent", `${launchAgent.installed ? paint("installed", color.green) : paint("not installed", color.red)} / ${launchAgent.loaded ? paint("loaded", color.green) : paint("not loaded", color.yellow)}`)
  ]));

  if (calibration.active) {
    const acceptable = calibration.acceptableSets.flat();
    const summary = await calibrationSummary().catch(() => null);
    const calibrationLines = [
      row("Phase", badge(calibration.phase, { idle: color.gray, forbidden: color.red, acceptable: color.green })),
      row("Forbidden", `${calibration.forbidden.length} samples · median ${median(calibration.forbidden) ?? "n/a"} · var ${variance(calibration.forbidden).toFixed(1)}`),
      row("Acceptable", `${calibration.acceptableSets.length} sets · ${acceptable.length} samples · median ${median(acceptable) ?? "n/a"} · var ${variance(acceptable).toFixed(1)}`),
      row("Live RSSI", `${paint(sparkline(calibration.live), color.cyan)} ${calibration.live.at(-1) ?? ""}`)
    ];
    if (summary) calibrationLines.push(row("Eval", `confidence ${badge(summary.confidence, { high: color.green, medium: color.yellow, low: color.red })} · separation ${summary.separation} · armed ${summary.armedEligible ? paint("yes", color.green) : paint("no", color.red)}`));
    lines.push("");
    lines.push(box("Calibration", calibrationLines));
  }

  const eventLines = recentEvents.length === 0
    ? [paint("(none)", color.dim)]
    : recentEvents.map((event) => `${paint(String(event.index).padStart(4), color.gray)} ${paint(event.timestamp, color.dim)} ${event.kind}`);
  lines.push("");
  lines.push(box("Recent events", eventLines));
  lines.push("");
  if (lastCommandMessage) lines.push(lastCommandMessage);
  lines.push(paint("Commands", color.bold));
  lines.push("  start <forbidden|acceptable|uncertain|missing>   stop   mode <dryRun|armed>");
  lines.push("  inject <classification>   replay <scenario>   launchagent <install|restart|remove|status>");
  lines.push("  calibrate <start|forbidden-start|forbidden-stop|acceptable-start|acceptable-stop|finish>   q");

  lastRender = `${lines.join("\n")}\n`;
  if (isTTY) {
    readline.cursorTo(process.stdout, 0, 0);
    readline.clearScreenDown(process.stdout);
  }
  process.stdout.write(lastRender);
  rl.prompt(true);
}

async function runCommand(line) {
  const [cmd, arg] = line.trim().split(/\s+/, 2);
  if (!cmd) return;
  if (cmd === "q" || cmd === "quit" || cmd === "exit") process.exit(0);
  if (cmd === "start") await rpc("session.start", { classification: arg ?? "forbidden" });
  else if (cmd === "stop") await rpc("session.stop");
  else if (cmd === "mode") await rpc("enforcement.setMode", { mode: arg });
  else if (cmd === "inject") await rpc("simulation.inject", { classification: arg });
  else if (cmd === "replay") await rpc("simulation.replay", { scenario: arg });
  else if (cmd === "launchagent") {
    if (arg === "install") await rpc("launchAgent.install");
    else if (arg === "restart") await rpc("launchAgent.restart");
    else if (arg === "remove") await rpc("launchAgent.remove");
    else if (arg === "status") await rpc("launchAgent.status");
    else throw new Error("usage: launchagent install|restart|remove|status");
  }
  else if (cmd === "calibrate") {
    if (arg === "start") {
      calibration.active = true;
      calibration.phase = "idle";
      calibration.forbidden = [];
      calibration.acceptableSets = [[]];
      calibration.currentAcceptableIndex = 0;
      calibration.live = [];
    } else if (arg === "forbidden-start") {
      calibration.phase = "forbidden";
    } else if (arg === "forbidden-stop") {
      calibration.phase = "idle";
    } else if (arg === "acceptable-start") {
      calibration.phase = "acceptable";
    } else if (arg === "acceptable-stop") {
      calibration.phase = "idle";
    } else if (arg === "acceptable-add") {
      calibration.acceptableSets.push([]);
      calibration.currentAcceptableIndex = calibration.acceptableSets.length - 1;
      calibration.phase = "acceptable";
    } else if (arg === "redo-forbidden") {
      calibration.forbidden = [];
      calibration.phase = "forbidden";
    } else if (arg === "redo-acceptable") {
      calibration.acceptableSets[calibration.currentAcceptableIndex] = [];
      calibration.phase = "acceptable";
    } else if (arg === "finish") {
      calibration.phase = "idle";
    }
  }
}

const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
rl.setPrompt(paint("faraday> ", color.bold + color.cyan));

setInterval(() => {
  // Do not redraw while user is typing; readline otherwise loses visible input.
  if (rl.line.length > 0) return;
  render().catch((error) => {
    lastCommandMessage = paint(`Render error: ${error.message}`, color.red);
  });
}, 1000);
render().catch((error) => {
  lastCommandMessage = paint(`Render error: ${error.message}`, color.red);
});

rl.on("line", async (line) => {
  try {
    await runCommand(line);
    lastCommandMessage = paint(`✓ ${line.trim() || "noop"}`, color.green);
  } catch (error) {
    lastCommandMessage = paint(`Command error: ${error.message}`, color.red);
  }
  await render().catch((error) => {
    lastCommandMessage = paint(`Render error: ${error.message}`, color.red);
  });
});

rl.on("close", () => {
  if (isTTY) process.stdout.write(color.reset);
  process.exit(0);
});
