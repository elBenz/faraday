#!/usr/bin/env bun
import net from "node:net";
import readline from "node:readline";
import os from "node:os";
import path from "node:path";

const socketPath = process.env.FARADAY_SOCKET ?? path.join(os.homedir(), ".faraday", "faraday.sock");
let nextId = 1;
let afterIndex = -1;

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

    client.on("connect", () => client.write(request));
    client.on("data", (chunk) => {
      buffer += chunk.toString("utf8");
      const idx = buffer.indexOf("\n");
      if (idx === -1) return;
      client.end();
      try {
        const payload = JSON.parse(buffer.slice(0, idx));
        if (payload.error) reject(new Error(`${payload.error.code}: ${payload.error.message}`));
        else resolve(payload.result ?? {});
      } catch (error) {
        reject(error);
      }
    });
    client.on("error", reject);
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
  const [status, tail, launchAgent] = await Promise.all([
    rpc("faraday.status"),
    rpc("events.tail", { afterIndex }),
    rpc("launchAgent.status").catch(() => ({ installed: false, loaded: false }))
  ]);
  const events = tail.events ?? [];
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

  process.stdout.write("\x1Bc");
  console.log("Faraday Session Dashboard\n");
  console.log(`Socket: ${socketPath}`);
  console.log(`Source: ${status.observationSource}`);
  console.log(`Mode: ${status.enforcementMode}`);
  console.log(`Session: ${status.sessionState}`);
  console.log(`Classification: ${status.lastClassification ?? "n/a"}`);
  console.log(`Calibration confidence: ${status.calibrationConfidence ?? "n/a"}`);
  console.log(`Overlay: ${status.overlayState ?? "n/a"}`);
  console.log(`Countdown: ${status.countdownSeconds ?? "n/a"}`);
  console.log(`LaunchAgent: installed=${launchAgent.installed} loaded=${launchAgent.loaded}`);

  if (calibration.active) {
    const acceptable = calibration.acceptableSets.flat();
    const summary = await calibrationSummary().catch(() => null);
    console.log("\nCalibration wizard:");
    console.log(`  phase=${calibration.phase}`);
    console.log(`  forbidden samples=${calibration.forbidden.length} median=${median(calibration.forbidden) ?? "n/a"} var=${variance(calibration.forbidden).toFixed(1)}`);
    console.log(`  acceptable sets=${calibration.acceptableSets.length} total samples=${acceptable.length} median=${median(acceptable) ?? "n/a"} var=${variance(acceptable).toFixed(1)}`);
    console.log(`  live ${sparkline(calibration.live)} ${calibration.live.at(-1) ?? ""}`);
    if (summary) {
      console.log(`  confidence=${summary.confidence} separation=${summary.separation} armedEligible=${summary.armedEligible}`);
    }
  }

  console.log("\nRecent events:");
  if (events.length === 0) console.log("  (none)");
  for (const event of events.slice(-10)) {
    console.log(`  [${event.index}] ${event.timestamp} ${event.kind}`);
  }
  console.log("\nCommands: start forbidden|acceptable|uncertain|missing | stop | mode dryRun|armed | inject <classification> | replay startActivationViolationDryRun|missingDegraded | launchagent install|restart|remove|status | calibrate start|forbidden-start|forbidden-stop|acceptable-start|acceptable-stop|acceptable-add|redo-forbidden|redo-acceptable|finish | q");
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
setInterval(() => render().catch((error) => console.error(`Render error: ${error.message}`)), 1000);
render().catch((error) => console.error(`Render error: ${error.message}`));

rl.on("line", async (line) => {
  try {
    await runCommand(line);
    await render();
  } catch (error) {
    console.error(`Command error: ${error.message}`);
  }
});
