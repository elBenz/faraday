import net from "node:net";
import os from "node:os";
import path from "node:path";

export const socketPath = process.env.FARADAY_SOCKET ?? path.join(os.homedir(), ".faraday", "faraday.sock");
let nextId = 1;

export function rpc(method, params = {}, timeoutMs = 1200) {
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

    const timer = setTimeout(() => finish(reject, new Error(`RPC timeout for ${method}; is FaradayDaemon running?`)), timeoutMs);
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
