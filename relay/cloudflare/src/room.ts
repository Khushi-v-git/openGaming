import { DurableObject } from "cloudflare:workers";
import type { Env } from "./env";
import {
  CLOSE_CODES,
  KEEPALIVE_REQUEST,
  KEEPALIVE_RESPONSE,
  control,
  errorFrame,
  parsePeer,
  splitPeer,
  type RelayError,
} from "./frames";
import { Bucket, readLimits, type Limits } from "./limits";
import { hashToken, randomToken, safeEqual } from "./room_code";

/** What each socket carries across hibernation (at most 16 KB). */
interface Attachment {
  role: "host" | "peer" | "resume";
  peer: number; // joiner id (>= 2); 0 for the host
  seen: number; // when the socket connected (liveness also uses the runtime's auto-response time)
  gone?: boolean; // already handled as disconnected
  kicked?: boolean;
  replaced?: boolean; // an older host socket that a resume replaced
  quit?: boolean; // the host said it is leaving for good
}

const ACTIVITY_WRITE_EVERY_MS = 5 * 60 * 1000; // idle expiry is checked coarsely, so write rarely
const KICK_CLOSE_MS = 1500;

/**
 * One room. A dumb forwarder: it routes frames between the room's host and its joiners and never
 * interprets payloads. Everything that must survive hibernation lives in socket attachments or in
 * this object's SQLite storage; the in-memory maps below only hold rate-limit buckets.
 */
export class Room extends DurableObject<Env> {
  private limits: Limits;
  private buckets = new WeakMap<WebSocket, { bucket: Bucket; violations: number }>();
  private lastActivity = 0;
  private persistedActivity = 0;
  private closing = false;

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.limits = readLimits(env as unknown as Record<string, unknown>);
    if (env.DEBUG_LIFECYCLE === "1") console.log(`[room] constructed t=${Date.now()}`); // runs again after every hibernation
    this.ctx.blockConcurrencyWhile(async () => this.ensureSchema());
    // Answered by the runtime without waking the object and without wall-clock time.
    this.ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair(KEEPALIVE_REQUEST, KEEPALIVE_RESPONSE));
  }

  private ensureSchema(): void {
    this.sql.exec("CREATE TABLE IF NOT EXISTS meta (k TEXT PRIMARY KEY, v TEXT NOT NULL)");
    this.sql.exec("CREATE TABLE IF NOT EXISTS queue (id INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT NOT NULL, peer INTEGER NOT NULL, text TEXT NOT NULL)");
  }

  private get sql(): SqlStorage {
    return this.ctx.storage.sql;
  }

  // ---- entry: the Worker routes upgrades here -------------------------------------------------------

  async fetch(request: Request): Promise<Response> {
    if (request.headers.get("Upgrade") !== "websocket") return new Response("expected a WebSocket", { status: 426 });
    const intent = request.headers.get("x-relay-intent");
    const code = request.headers.get("x-relay-code") ?? "";
    switch (intent) {
      case "host":
        return this.acceptHost(code);
      case "join":
        return this.acceptJoiner();
      case "resume":
        return this.acceptResume();
      default:
        return fail("BAD_FRAME", 400);
    }
  }

  private async acceptHost(code: string): Promise<Response> {
    if (this.roomExists()) return fail("RELAY_BUSY", 409); // the code is taken: the Worker tries another
    this.ensureSchema(); // a closed room's storage was deleted entirely
    const token = randomToken();
    const now = Date.now();
    this.setMeta("code", code);
    this.setMeta("host_hash", await hashToken(token));
    this.setMeta("created", String(now));
    this.setMeta("last_activity", String(now));
    this.setMeta("next_peer", "2");
    this.setMeta("resumes", "0");
    this.setMeta("buf_total", "0");
    this.lastActivity = this.persistedActivity = now;
    this.closing = false;
    const [client, server] = this.newPair();
    this.ctx.acceptWebSocket(server);
    this.attach(server, { role: "host", peer: 0, seen: now });
    server.send(control({ t: "hosted", code, token, ...this.advice() }));
    await this.scheduleAlarm();
    return new Response(null, { status: 101, webSocket: client });
  }

  private acceptJoiner(): Response {
    if (!this.roomExists()) return fail("ROOM_NOT_FOUND", 404);
    if (this.hostIsAway()) return fail("HOST_AWAY", 423);
    if (this.liveSockets().length >= this.limits.maxSockets) return fail("ROOM_FULL", 409);
    const peer = Number(this.getMeta("next_peer") ?? "2");
    this.setMeta("next_peer", String(peer + 1));
    const [client, server] = this.newPair();
    this.ctx.acceptWebSocket(server);
    this.attach(server, { role: "peer", peer, seen: Date.now() });
    server.send(control({ t: "joined", ...this.advice() }));
    this.toHost("J" + peer);
    return new Response(null, { status: 101, webSocket: client });
  }

  private acceptResume(): Response {
    if (!this.roomExists()) return fail("ROOM_NOT_FOUND", 404);
    const [client, server] = this.newPair();
    this.ctx.acceptWebSocket(server);
    this.attach(server, { role: "resume", peer: 0, seen: Date.now() });
    // A socket that never proves who it is gets closed (a short timer; it ends well before any hibernation).
    setTimeout(() => {
      const att = this.attachmentOf(server);
      if (att && att.role === "resume" && !att.gone) this.drop(server, "TIMEOUT");
    }, this.limits.handshakeSec * 1000);
    return new Response(null, { status: 101, webSocket: client });
  }

  // ---- hibernation handlers ---------------------------------------------------------------------------

  async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer): Promise<void> {
    if (this.env.DEBUG_LIFECYCLE === "1") console.log(`[room] message t=${Date.now()}`);
    const att = this.attachmentOf(ws);
    if (!att || att.gone || this.closing) return;
    if (typeof message !== "string") return this.drop(ws, "BAD_FRAME");
    if (message.length > this.limits.maxFrameChars) return this.drop(ws, "TOO_LARGE");
    if (att.role === "resume") return this.handleResume(ws, att, message);
    if (att.kicked) return; // told to go: nothing more is forwarded
    if (!this.roomExists()) return;
    if (!this.allow(ws, att)) return;
    this.touch();
    if (att.role === "host") this.fromHost(ws, message);
    else this.fromPeer(att, message);
  }

  async webSocketClose(ws: WebSocket): Promise<void> {
    this.onGone(ws);
    try {
      ws.close();
    } catch {
      /* already closed */
    }
  }

  async webSocketError(ws: WebSocket): Promise<void> {
    this.onGone(ws);
  }

  // ---- routing -------------------------------------------------------------------------------------------

  private fromPeer(att: Attachment, frame: string): void {
    if (frame[0] !== "M") return;
    const payload = frame.slice(1);
    if (!this.hostIsAway()) {
      this.toHost("M" + att.peer + ":" + payload);
      return;
    }
    this.buffer(att.peer, payload);
  }

  private fromHost(ws: WebSocket, frame: string): void {
    const body = frame.slice(1);
    switch (frame[0]) {
      case "S": {
        const parts = splitPeer(body);
        const target = parts && this.peerSocket(parts.peer);
        if (target && parts) target.send("M" + parts.rest);
        break;
      }
      case "K": {
        const parts = splitPeer(body);
        const target = parts && this.peerSocket(parts.peer);
        if (target && parts) this.kick(target, /^[A-Z_]{1,24}$/.test(parts.rest) ? parts.rest : "KICKED");
        break;
      }
      case "Q": {
        const att = this.attachmentOf(ws);
        if (att) {
          att.quit = true;
          this.attach(ws, att);
        }
        this.closeRoom("ROOM_CLOSED");
        break;
      }
    }
  }

  private toHost(frame: string): void {
    const host = this.hostSocket();
    if (host) host.send(frame);
  }

  /** The host is away: keep a bounded number of messages for it, in order. */
  private buffer(peer: number, payload: string): void {
    const L = this.limits;
    const perPeer = this.scalar("SELECT COUNT(*) FROM queue WHERE kind = 'M' AND peer = ?", peer);
    const chars = this.scalar("SELECT COALESCE(SUM(LENGTH(text)), 0) FROM queue WHERE kind = 'M'");
    const lifetime = Number(this.getMeta("buf_total") ?? "0");
    if (perPeer >= L.bufferPerPeer || chars + payload.length > L.bufferMaxChars || lifetime >= L.bufferRoomLifetime) {
      const target = this.peerSocket(peer);
      if (target) this.kick(target, "HOST_AWAY"); // the joiner takes the normal rejoin path
      return;
    }
    this.sql.exec("INSERT INTO queue (kind, peer, text) VALUES ('M', ?, ?)", peer, payload);
    this.setMeta("buf_total", String(lifetime + 1));
  }

  // ---- disconnects -----------------------------------------------------------------------------------------

  private onGone(ws: WebSocket): void {
    const att = this.attachmentOf(ws);
    if (!att || att.gone) return;
    att.gone = true;
    this.attach(ws, att);
    if (this.closing || !this.roomExists()) return;
    if (att.role === "peer") {
      if (this.hostIsAway()) this.sql.exec("INSERT INTO queue (kind, peer, text) VALUES ('L', ?, '')", att.peer);
      else this.toHost("L" + att.peer);
    } else if (att.role === "host" && !att.replaced && !att.quit) {
      this.hostLost();
    }
  }

  private hostLost(): void {
    if (Number(this.getMeta("resumes") ?? "0") >= this.limits.maxHostResumes) {
      this.closeRoom("ROOM_CLOSED");
      return;
    }
    this.setMeta("host_gone_at", String(Date.now()));
    for (const ws of this.liveSockets()) if (this.attachmentOf(ws)?.role === "peer") ws.send("H");
    void this.scheduleAlarm();
  }

  private async handleResume(ws: WebSocket, att: Attachment, frame: string): Promise<void> {
    const stored = this.getMeta("host_hash");
    if (frame[0] !== "R" || !stored || !safeEqual(await hashToken(frame.slice(1)), stored)) {
      return this.drop(ws, "BAD_TOKEN");
    }
    const resumes = Number(this.getMeta("resumes") ?? "0");
    if (resumes >= this.limits.maxHostResumes) return this.drop(ws, "RATE_LIMITED");
    const old = this.hostSocket();
    if (old) {
      const oldAtt = this.attachmentOf(old);
      if (oldAtt) {
        oldAtt.replaced = true;
        oldAtt.gone = true;
        this.attach(old, oldAtt);
      }
      this.send(old, errorFrame("REPLACED"));
      this.closeQuietly(old, "REPLACED");
    }
    att.role = "host";
    this.attach(ws, att);
    this.setMeta("resumes", String(resumes + 1));
    ws.send(control({ t: "resumed", ...this.advice() }));
    // Replay what happened while the host was away, in the order it happened.
    const rows = [...this.sql.exec<{ kind: string; peer: number; text: string }>("SELECT kind, peer, text FROM queue ORDER BY id")];
    for (const row of rows) ws.send(row.kind === "M" ? "M" + row.peer + ":" + row.text : "L" + row.peer);
    if (rows.length > 0) this.sql.exec("DELETE FROM queue");
    if (this.hostIsAway()) {
      this.sql.exec("DELETE FROM meta WHERE k = 'host_gone_at'");
      for (const peerWs of this.liveSockets()) if (this.attachmentOf(peerWs)?.role === "peer") peerWs.send("B");
    }
    this.touch();
    await this.scheduleAlarm();
  }

  // ---- the alarm: expiry and dead sockets -----------------------------------------------------------------

  async alarm(): Promise<void> {
    if (!this.roomExists()) return;
    const L = this.limits;
    const now = Date.now();
    const created = Number(this.getMeta("created") ?? now);
    const activity = Math.max(this.lastActivity, Number(this.getMeta("last_activity") ?? created));
    const goneAt = this.getMeta("host_gone_at");
    if (now - created > L.maxRoomAgeSec * 1000 || now - activity > L.idleTtlSec * 1000) {
      this.closeRoom("ROOM_CLOSED");
      return;
    }
    if (goneAt && now - Number(goneAt) >= L.hostGraceSec * 1000) {
      this.closeRoom("ROOM_CLOSED");
      return;
    }
    for (const ws of this.liveSockets()) {
      const att = this.attachmentOf(ws);
      if (!att || att.role === "resume") continue;
      const heard = Math.max(att.seen, this.ctx.getWebSocketAutoResponseTimestamp(ws)?.getTime() ?? 0);
      if (now - heard > L.deadSec * 1000) {
        this.onGone(ws);
        this.closeQuietly(ws, "TIMEOUT");
      }
    }
    await this.scheduleAlarm();
  }

  private async scheduleAlarm(): Promise<void> {
    let next = Date.now() + this.limits.sweepSec * 1000;
    const goneAt = this.getMeta("host_gone_at");
    if (goneAt) next = Math.min(next, Number(goneAt) + this.limits.hostGraceSec * 1000 + 50);
    await this.ctx.storage.setAlarm(next);
  }

  // ---- helpers ------------------------------------------------------------------------------------------------

  private closeRoom(code: RelayError): void {
    if (this.closing) return;
    this.closing = true;
    for (const ws of this.ctx.getWebSockets()) {
      const att = this.attachmentOf(ws);
      if (att) {
        att.gone = true;
        this.attach(ws, att);
      }
      this.send(ws, "X" + code);
    }
    const sockets = this.ctx.getWebSockets();
    setTimeout(() => sockets.forEach((ws) => this.closeQuietly(ws, code)), KICK_CLOSE_MS);
    void this.ctx.storage.deleteAlarm();
    void this.ctx.storage.deleteAll();
  }

  /** Tells the peer the connection is ending, after anything already sent; they close it themselves. */
  private kick(ws: WebSocket, code: string): void {
    const att = this.attachmentOf(ws);
    if (!att || att.kicked || att.gone) return;
    att.kicked = true;
    this.attach(ws, att);
    this.send(ws, "X" + code);
    setTimeout(() => {
      this.onGone(ws);
      this.closeQuietly(ws, "KICKED");
    }, KICK_CLOSE_MS);
  }

  /** Protocol violation or timeout: say why and close at once. */
  private drop(ws: WebSocket, code: RelayError): void {
    this.send(ws, errorFrame(code));
    this.onGone(ws);
    this.closeQuietly(ws, code);
  }

  private allow(ws: WebSocket, att: Attachment): boolean {
    let entry = this.buckets.get(ws);
    const now = Date.now();
    if (!entry) {
      const rate = att.role === "host" ? this.limits.hostRate : this.limits.peerRate;
      entry = { bucket: new Bucket(rate.burst, rate.perSec, now), violations: 0 };
      this.buckets.set(ws, entry);
    }
    if (entry.bucket.allow(now)) return true;
    entry.violations += 1;
    if (entry.violations > this.limits.maxViolations) this.drop(ws, "RATE_LIMITED");
    return false;
  }

  private touch(): void {
    const now = Date.now();
    this.lastActivity = now;
    if (now - this.persistedActivity > ACTIVITY_WRITE_EVERY_MS) {
      this.persistedActivity = now;
      this.setMeta("last_activity", String(now));
    }
  }

  private advice(): Record<string, unknown> {
    const L = this.limits;
    return { ping_sec: L.pingSec, watchdog_sec: L.watchdogSec, grace_sec: L.hostGraceSec, max_sockets: L.maxSockets };
  }

  private hostSocket(): WebSocket | undefined {
    return this.liveSockets().find((ws) => this.attachmentOf(ws)?.role === "host");
  }

  private peerSocket(peer: number): WebSocket | undefined {
    return this.liveSockets().find((ws) => {
      const att = this.attachmentOf(ws);
      return att?.role === "peer" && att.peer === peer && !att.kicked;
    });
  }

  private liveSockets(): WebSocket[] {
    return this.ctx.getWebSockets().filter((ws) => {
      const att = this.attachmentOf(ws);
      return att && !att.gone;
    });
  }

  private hostIsAway(): boolean {
    return this.getMeta("host_gone_at") !== null;
  }

  private roomExists(): boolean {
    return this.getMeta("code") !== null;
  }

  private newPair(): [WebSocket, WebSocket] {
    const pair = new WebSocketPair();
    return [pair[0], pair[1]];
  }

  private attach(ws: WebSocket, att: Attachment): void {
    try {
      ws.serializeAttachment(att);
    } catch {
      /* the socket is already closed */
    }
  }

  private attachmentOf(ws: WebSocket): Attachment | null {
    try {
      return ws.deserializeAttachment() as Attachment | null;
    } catch {
      return null;
    }
  }

  private send(ws: WebSocket, frame: string): void {
    try {
      ws.send(frame);
    } catch {
      /* closed */
    }
  }

  private closeQuietly(ws: WebSocket, code: string): void {
    try {
      ws.close(CLOSE_CODES[code] ?? 1000, code);
    } catch {
      /* already closed */
    }
  }

  private getMeta(key: string): string | null {
    try {
      const rows = [...this.sql.exec<{ v: string }>("SELECT v FROM meta WHERE k = ?", key)];
      return rows.length > 0 ? rows[0].v : null;
    } catch (error) {
      if (String(error).includes("no such table")) return null; // the room was closed and its storage deleted
      throw error;
    }
  }

  private setMeta(key: string, value: string): void {
    this.sql.exec("INSERT OR REPLACE INTO meta (k, v) VALUES (?, ?)", key, value);
  }

  private scalar(query: string, ...bindings: (string | number)[]): number {
    const row = this.sql.exec(query, ...bindings).raw().next().value as unknown[] | undefined;
    return row ? Number(row[0]) : 0;
  }
}

function fail(code: RelayError, status: number): Response {
  return Response.json({ error: code }, { status });
}

// Exported for tests: the helper that parses "J2"/"L2" style frames.
export { parsePeer };
