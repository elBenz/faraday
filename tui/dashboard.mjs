#!/usr/bin/env bun
import net from "node:net";
import readline from "node:readline";
import os from "node:os";
import path from "node:path";

const socketPath = process.env.FARADAY_SOCKET ?? path.join(os.homedir(), ".faraday", "faraday.sock");
let nextId = 1;
let afterIndex = -1;

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

async function render() {
  const status = await rpc("faraday.status");
  const tail = await rpc("events.tail", { afterIndex });
  const events = tail.events ?? [];
  if (typeof tail.nextIndex === "number") afterIndex = tail.nextIndex;

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
  console.log("\nRecent events:");
  if (events.length === 0) console.log("  (none)");
  for (const event of events.slice(-10)) {
    console.log(`  [${event.index}] ${event.timestamp} ${event.kind}`);
  }
  console.log("\nCommands: start forbidden|acceptable|uncertain|missing | stop | mode dryRun|armed | inject <classification> | replay startActivationViolationDryRun|missingDegraded | q");
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
