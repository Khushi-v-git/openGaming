import { SELF } from "cloudflare:test";

export interface Client {
  ws: WebSocket;
  frames: string[];
  closed: { code: number; reason: string } | null;
  send(frame: string | ArrayBuffer): void;
  close(code?: number): void;
}

/** Opens a WebSocket to the relay inside the test runtime. */
export async function connect(path: string): Promise<Client> {
  const response = await SELF.fetch("https://relay.test" + path, { headers: { Upgrade: "websocket" } });
  const ws = response.webSocket;
  if (!ws) throw new Error(`no WebSocket for ${path}: HTTP ${response.status}`);
  ws.accept();
  const client: Client = {
    ws,
    frames: [],
    closed: null,
    send: (frame) => ws.send(frame),
    close: (code = 1000) => ws.close(code),
  };
  ws.addEventListener("message", (event) => client.frames.push(String(event.data)));
  ws.addEventListener("close", (event) => {
    client.closed = { code: event.code, reason: event.reason };
  });
  return client;
}

export async function until(condition: () => boolean, what = "condition", ms = 4000): Promise<void> {
  const start = Date.now();
  while (!condition()) {
    if (Date.now() - start > ms) throw new Error(`timed out waiting for ${what}`);
    await new Promise((r) => setTimeout(r, 5));
  }
}

export const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

export interface Hosted {
  code: string;
  token: string;
  host: Client;
  info: Record<string, unknown>;
}

export function parseControl(frame: string): Record<string, unknown> {
  if (frame[0] !== "C") throw new Error("not a control frame: " + frame);
  return JSON.parse(frame.slice(1));
}

/** A host with a fresh room (random code). */
export async function newRoom(): Promise<Hosted> {
  const host = await connect("/host");
  await until(() => host.frames.length > 0, "hosted frame");
  const info = parseControl(host.frames.shift()!);
  return { code: info.code as string, token: info.token as string, host, info };
}

export interface Joined {
  client: Client;
  peer: number;
}

/** A joiner; waits for the joined frame and for the host to hear "J<peer>". */
export async function join(room: Hosted): Promise<Joined> {
  const before = room.host.frames.length;
  const client = await connect("/join/" + room.code);
  await until(() => client.frames.length > 0 || client.closed !== null, "joined frame");
  const first = client.frames[0];
  if (!first.startsWith('C{"t":"joined"')) throw new Error("join refused: " + first);
  client.frames.shift();
  await until(() => room.host.frames.length > before, "J frame");
  const note = room.host.frames[room.host.frames.length - 1];
  if (note[0] !== "J") throw new Error("expected J, got " + note);
  room.host.frames.pop();
  return { client, peer: Number(note.slice(1)) };
}

export async function expectRefusal(path: string): Promise<string> {
  const client = await connect(path);
  await until(() => client.frames.length > 0, "error frame");
  const control = parseControl(client.frames[0]);
  await until(() => client.closed !== null, "close");
  return String(control.code);
}

export async function resume(room: Hosted, token = room.token): Promise<Client> {
  const client = await connect("/resume/" + room.code);
  client.send("R" + token);
  return client;
}
