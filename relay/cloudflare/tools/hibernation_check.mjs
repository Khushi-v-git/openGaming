// Proves, against a local `wrangler dev`, that a room object hibernates between game messages and
// that keepalive pings (answered by the runtime) do not wake it.
//
//   npx wrangler dev --local --port 8787 --var DEBUG_LIFECYCLE:1 --var SWEEP_SEC:100000 --var DEAD_SEC:100000 > dev.log 2>&1 &
//   node tools/hibernation_check.mjs ws://127.0.0.1:8787 dev.log
//
// (The sweep alarm is pushed far away so it cannot wake the room during the experiment; the alarm's
// own cost is accounted for separately in docs/relay.md.)
//
// The Room logs "[room] constructed t=<ms>" every time it is (re)created, which happens on every
// wake-up from hibernation, and "[room] message t=<ms>" for every message that reaches its code.
// Auto-answered pings produce neither.
import { readFileSync } from "node:fs";

const [base = "ws://127.0.0.1:8787", logPath = "dev.log"] = process.argv.slice(2);
const PING_WINDOW_MS = 30000;
const SILENT_WINDOW_MS = 25000;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function stamps(kind) {
  const re = new RegExp(`\\[room\\] ${kind} t=(\\d+)`, "g");
  return [...readFileSync(logPath, "utf8").matchAll(re)].map((m) => Number(m[1]));
}
const between = (list, from, to) => list.filter((t) => t >= from && t <= to).length;

function open(path) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(base + path);
    const frames = [];
    ws.onmessage = (e) => frames.push(String(e.data));
    ws.onopen = () => resolve({ ws, frames });
    ws.onerror = () => reject(new Error("connect failed: " + path));
  });
}

const results = [];
function check(name, ok, detail) {
  results.push(ok);
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}${detail ? "  (" + detail + ")" : ""}`);
}

const host = await open("/host");
await sleep(300);
const code = JSON.parse(host.frames[0].slice(1)).code;
const joiner = await open("/join/" + code);
await sleep(300);
joiner.ws.send("Mhello");
await sleep(500);
check("a game message reaches the host", host.frames.includes("M2:hello"));

// 1. Pings only, for 30 s: the room must not be created again and its code must not run.
await sleep(12000); // let it go idle and hibernate first
const pingStart = Date.now();
let pings = 0;
while (Date.now() - pingStart < PING_WINDOW_MS) {
  host.ws.send("ping");
  joiner.ws.send("ping");
  pings += 2;
  await sleep(5000);
}
const pingEnd = Date.now();
await sleep(2500); // let wrangler flush its log
check("every keepalive ping was answered", host.frames.filter((f) => f === "pong").length >= pings / 2 && joiner.frames.filter((f) => f === "pong").length >= pings / 2, `${pings} pings sent`);
check("pings never ran the room's code", between(stamps("message"), pingStart, pingEnd) === 0);
check("pings never woke the room", between(stamps("constructed"), pingStart, pingEnd) === 0, `${between(stamps("constructed"), pingStart, pingEnd)} wake-ups in ${PING_WINDOW_MS / 1000} s`);

// 2. Nothing at all for a while, then a real message: the room must have hibernated and be woken for it.
await sleep(SILENT_WINDOW_MS);
const messageAt = Date.now();
joiner.ws.send("Mafter-idle");
await sleep(2500);
check("a game message after a silent period is delivered", host.frames.includes("M2:after-idle"));
check("the room was hibernated and woken for that message", between(stamps("constructed"), messageAt - 500, messageAt + 2000) >= 1);
host.ws.send("S2:reply");
await sleep(500);
check("room state survived hibernation (host to joiner still routes)", joiner.frames.includes("Mreply"));

host.ws.close();
joiner.ws.close();
process.exit(results.every(Boolean) ? 0 : 1);
