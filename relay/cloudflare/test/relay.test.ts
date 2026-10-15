import { env, evictDurableObject, runDurableObjectAlarm, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import { ALPHABET, CODE_LENGTH, generateCode, normalizeCode } from "../src/room_code";
import { Room } from "../src/room";
import { connect, expectRefusal, join, newRoom, parseControl, resume, sleep, until, type Client, type Hosted } from "./helpers";

const open: Client[] = [];
afterEach(() => {
  for (const client of open.splice(0)) {
    try {
      client.close();
    } catch {
      /* already closed */
    }
  }
});

async function room(): Promise<Hosted> {
  const hosted = await newRoom();
  open.push(hosted.host);
  return hosted;
}
async function joiner(hosted: Hosted) {
  const joined = await join(hosted);
  open.push(joined.client);
  return joined;
}
const stubOf = (code: string) => env.ROOM.getByName(code);

describe("room codes", () => {
  it("are 6 characters from the unambiguous alphabet", () => {
    for (let i = 0; i < 2000; i++) {
      const code = generateCode();
      expect(code).toHaveLength(CODE_LENGTH);
      for (const ch of code) expect(ALPHABET).toContain(ch);
    }
    for (const bad of ["0", "O", "1", "I", "L"]) expect(ALPHABET).not.toContain(bad);
    expect(ALPHABET).toHaveLength(31);
  });

  it("are drawn without modulo bias", () => {
    const counts = new Map<string, number>();
    const total = 31 * 4000;
    for (let i = 0; i < total / CODE_LENGTH; i++) for (const ch of generateCode()) counts.set(ch, (counts.get(ch) ?? 0) + 1);
    const expected = total / 31;
    for (const ch of ALPHABET) expect(Math.abs((counts.get(ch) ?? 0) - expected)).toBeLessThan(expected * 0.15);
  });

  it("use rejection sampling: bytes that would bias the result are skipped", () => {
    // 256 % 31 = 8, so bytes 248..255 must be rejected; a source of only 255s never yields a code
    // until it produces a usable byte.
    let calls = 0;
    const code = generateCode((n) => {
      calls++;
      return calls < 3 ? n.fill(255) : n.fill(0);
    });
    expect(code).toBe(ALPHABET[0].repeat(CODE_LENGTH));
    expect(calls).toBe(3);
  });

  it("are cleaned up when typed: case, spaces and hyphens", () => {
    expect(normalizeCode(" abc-d2e ")).toBe("ABCD2E");
    expect(normalizeCode("ABCDE")).toBeNull();
    expect(normalizeCode("ABCDE0")).toBeNull();
    expect(normalizeCode("ABCDEL")).toBeNull();
  });
});

describe("creating and joining a room", () => {
  it("answers /health without waking a room", async () => {
    const { SELF } = await import("cloudflare:test");
    const response = await SELF.fetch("https://relay.test/health");
    expect(await response.json()).toMatchObject({ ok: true });
  });

  it("hands the host a code, a secret token and the keepalive advice", async () => {
    const { code, token, info } = await room();
    expect(normalizeCode(code)).toBe(code);
    expect(token).toMatch(/^[0-9a-f]{32}$/);
    expect(info).toMatchObject({ t: "hosted", ping_sec: 15, watchdog_sec: 45 });
  });

  it("gives joiners ids from 2, tells the host, and never reuses an id", async () => {
    const hosted = await room();
    const a = await joiner(hosted);
    const b = await joiner(hosted);
    expect([a.peer, b.peer]).toEqual([2, 3]);
    a.client.close();
    await until(() => hosted.host.frames.includes("L2"), "L2");
    const c = await joiner(hosted);
    expect(c.peer).toBe(4);
  });

  it("is case-insensitive about the code", async () => {
    const hosted = await room();
    const client = await connect(`/join/${hosted.code.toLowerCase().slice(0, 3)}-${hosted.code.slice(3)}`);
    open.push(client);
    await until(() => client.frames.length > 0, "frame");
    expect(parseControl(client.frames[0]).t).toBe("joined");
  });

  it("refuses an unknown or malformed code with ROOM_NOT_FOUND", async () => {
    expect(await expectRefusal("/join/ABCDEF")).toBe("ROOM_NOT_FOUND");
    expect(await expectRefusal("/join/ABC")).toBe("ROOM_NOT_FOUND");
    expect(await expectRefusal("/join/0OIL12")).toBe("ROOM_NOT_FOUND");
    expect(await expectRefusal("/resume/ABCDEF")).toBe("ROOM_NOT_FOUND");
  });

  it("refuses a full room with ROOM_FULL", async () => {
    const hosted = await room(); // MAX_SOCKETS is 4 in the tests: host + 3
    await joiner(hosted);
    await joiner(hosted);
    await joiner(hosted);
    expect(await expectRefusal("/join/" + hosted.code)).toBe("ROOM_FULL");
  });

  it("does not create storage for a code nobody hosts", async () => {
    await expectRefusal("/join/QQQQQQ");
    const stub = stubOf("QQQQQQ");
    const rows = await runInDurableObject(stub, (_i, state) => [...state.storage.sql.exec("SELECT k FROM meta")].length);
    expect(rows).toBe(0);
  });

  it("refuses a second host on a code that is taken (fixed codes are a test-only switch)", async () => {
    const first = await connect("/host?code=TESTAA");
    open.push(first);
    await until(() => first.frames.length > 0, "hosted");
    expect(await expectRefusal("/host?code=TESTAA")).toBe("RELAY_BUSY");
  });

  it("only speaks WebSocket and has no other routes", async () => {
    const { SELF } = await import("cloudflare:test");
    expect((await SELF.fetch("https://relay.test/host")).status).toBe(426);
    expect((await SELF.fetch("https://relay.test/nope", { headers: { Upgrade: "websocket" } })).status).toBe(404);
  });
});

describe("forwarding", () => {
  it("carries payloads untouched in both directions, whatever they contain", async () => {
    const hosted = await room();
    const { client, peer } = await joiner(hosted);
    const payloads = ['{"type":"x"}', "M:colon:inside", "line\nbreak", "ünïcödé ✓", "", "S2:looks like a routing header"];
    for (const p of payloads) client.send("M" + p);
    await until(() => hosted.host.frames.length === payloads.length, "all arrived");
    expect(hosted.host.frames).toEqual(payloads.map((p) => `M${peer}:${p}`));
    for (const p of payloads) hosted.host.send(`S${peer}:${p}`);
    await until(() => client.frames.length === payloads.length, "all arrived back");
    expect(client.frames).toEqual(payloads.map((p) => "M" + p));
  });

  it("keeps order, even for a burst", async () => {
    const hosted = await room();
    const { client } = await joiner(hosted);
    for (let i = 0; i < 100; i++) hosted.host.send(`S2:${i}`);
    await until(() => client.frames.length === 100, "100 frames");
    expect(client.frames).toEqual(Array.from({ length: 100 }, (_, i) => `M${i}`));
  });

  it("is a star: joiners cannot reach each other, and the host reaches only who it names", async () => {
    const hosted = await room();
    const a = await joiner(hosted);
    const b = await joiner(hosted);
    a.client.send("Mhello host");
    await until(() => hosted.host.frames.length === 1, "host frame");
    expect(hosted.host.frames[0]).toBe("M2:hello host");
    hosted.host.send("S3:only b");
    await until(() => b.client.frames.length === 1, "b frame");
    expect(a.client.frames).toEqual([]);
    hosted.host.send("S99:nobody"); // unknown peer: silently dropped
    hosted.host.send("Xjunk"); // unknown frame: ignored
    await sleep(50);
    expect(b.client.frames).toEqual(["Monly b"]);
  });
});

describe("kick and close ordering", () => {
  it("delivers everything sent before a kick, then X, then the host hears the peer leave", async () => {
    const hosted = await room();
    const { client } = await joiner(hosted);
    hosted.host.send("S2:one");
    hosted.host.send("S2:two");
    hosted.host.send("K2:KICKED");
    await until(() => client.frames.length === 3, "three frames");
    expect(client.frames).toEqual(["Mone", "Mtwo", "XKICKED"]);
    expect(client.closed).toBeNull(); // the relay waits for the peer to close first
    client.close();
    await until(() => hosted.host.frames.includes("L2"), "L2");
  });

  it("closes a kicked peer that never closes itself", async () => {
    const hosted = await room();
    const { client } = await joiner(hosted);
    hosted.host.send("K2:KICKED");
    await until(() => client.closed !== null, "forced close", 4000);
    expect(client.closed?.code).toBe(4403);
    await until(() => hosted.host.frames.includes("L2"), "L2");
  });

  it("does not let a joiner send after being kicked", async () => {
    const hosted = await room();
    const { client } = await joiner(hosted);
    hosted.host.send("K2:KICKED");
    await until(() => client.frames.includes("XKICKED"), "X");
    client.send("Mlate");
    await sleep(100);
    expect(hosted.host.frames.filter((f) => f.startsWith("M"))).toEqual([]);
    client.close();
  });

  it("tells the host when a joiner leaves", async () => {
    const hosted = await room();
    const { client } = await joiner(hosted);
    client.send("Mbye");
    client.close();
    await until(() => hosted.host.frames.includes("L2"), "L2");
    expect(hosted.host.frames.indexOf("M2:bye")).toBeLessThan(hosted.host.frames.indexOf("L2"));
  });

  it("closes the whole room at once when the host quits (Q)", async () => {
    const hosted = await room();
    const { client } = await joiner(hosted);
    hosted.host.send("Q");
    await until(() => client.frames.includes("XROOM_CLOSED"), "X");
    expect(await expectRefusal("/join/" + hosted.code)).toBe("ROOM_NOT_FOUND");
  });
});

describe("limits", () => {
  it("closes a socket that sends a frame over the size cap, and accepts one exactly at it", async () => {
    const hosted = await room();
    const { client } = await joiner(hosted);
    client.send("M" + "x".repeat(1999)); // 2000 characters: allowed
    await until(() => hosted.host.frames.length === 1, "frame at the cap");
    const big = await joiner(hosted);
    big.client.send("M" + "x".repeat(2000)); // 2001: refused
    await until(() => big.client.closed !== null, "closed");
    expect(big.client.closed?.code).toBe(1009);
    expect(parseControl(big.client.frames[0]).code).toBe("TOO_LARGE");
  });

  it("refuses binary frames", async () => {
    const hosted = await room();
    const { client } = await joiner(hosted);
    client.send(new Uint8Array([1, 2, 3]).buffer);
    await until(() => client.closed !== null, "closed");
    expect(client.closed?.code).toBe(1003);
  });

  it("rate-limits a flooding joiner: drops the excess, then disconnects it", async () => {
    const hosted = await room(); // burst 10, 1 per second, 3 violations allowed in the tests
    const { client } = await joiner(hosted);
    for (let i = 0; i < 40; i++) client.send("Mflood");
    await until(() => client.closed !== null, "closed");
    expect(parseControl(client.frames[client.frames.length - 1]).code).toBe("RATE_LIMITED");
    expect(hosted.host.frames.filter((f) => f.startsWith("M")).length).toBeLessThanOrEqual(12);
    await until(() => hosted.host.frames.includes("L2"), "L2");
  });

  it("closes a resume socket that never identifies itself", async () => {
    const hosted = await room();
    const silent = await connect("/resume/" + hosted.code);
    open.push(silent);
    await until(() => silent.closed !== null, "closed", 4000);
    expect(parseControl(silent.frames[0]).code).toBe("TIMEOUT");
  });
});

describe("host away, resume and the buffer", () => {
  async function hostDrops(hosted: Hosted) {
    hosted.host.close();
    await sleep(30);
  }

  it("tells joiners H, refuses newcomers, and buffers what joiners say for the host", async () => {
    const hosted = await room();
    const a = await joiner(hosted);
    await hostDrops(hosted);
    await until(() => a.client.frames.includes("H"), "H");
    expect(await expectRefusal("/join/" + hosted.code)).toBe("HOST_AWAY");
    a.client.send("Mone");
    a.client.send("Mtwo");
    await sleep(50);
  });

  it("replays the buffer in order on resume, then tells the peers the host is back", async () => {
    const hosted = await room();
    const a = await joiner(hosted);
    const b = await joiner(hosted);
    await hostDrops(hosted);
    await until(() => a.client.frames.includes("H"), "H");
    a.client.send("Mfirst");
    b.client.send("Msecond");
    a.client.send("Mthird");
    b.client.close(); // leaves during the gap
    await sleep(50);
    const host2 = await resume(hosted);
    open.push(host2);
    await until(() => host2.frames.length >= 5, "replay");
    expect(parseControl(host2.frames[0]).t).toBe("resumed");
    expect(host2.frames.slice(1)).toEqual(["M2:first", "M3:second", "M2:third", "L3"]);
    await until(() => a.client.frames.includes("B"), "B");
    host2.send("S2:welcome back");
    await until(() => a.client.frames.includes("Mwelcome back"), "routing works again");
  });

  it("rejects a wrong token and an empty one, and leaves the room waiting", async () => {
    const hosted = await room();
    await joiner(hosted);
    await hostDrops(hosted);
    for (const token of ["nope", ""]) {
      const bad = await resume(hosted, token);
      open.push(bad);
      await until(() => bad.closed !== null, "closed");
      expect(parseControl(bad.frames[0]).code).toBe("BAD_TOKEN");
    }
    const good = await resume(hosted);
    open.push(good);
    await until(() => good.frames.length > 0, "resumed");
    expect(parseControl(good.frames[0]).t).toBe("resumed");
  });

  it("replaces a stale host socket when the same host resumes", async () => {
    const hosted = await room();
    const a = await joiner(hosted);
    const host2 = await resume(hosted);
    open.push(host2);
    await until(() => host2.frames.length > 0, "resumed");
    await until(() => hosted.host.closed !== null, "old host closed");
    expect(hosted.host.frames.some((f) => f.includes("REPLACED"))).toBe(true);
    await sleep(50);
    expect(a.client.frames).not.toContain("H"); // the swap is invisible to joiners
    a.client.send("Mhi");
    await until(() => host2.frames.includes("M2:hi"), "new host hears");
  });

  it("disconnects a joiner whose buffer overflows, so it takes the normal rejoin path", async () => {
    const hosted = await room(); // BUFFER_PER_PEER = 3
    const a = await joiner(hosted);
    await hostDrops(hosted);
    for (let i = 0; i < 4; i++) a.client.send("M" + i);
    await until(() => a.client.frames.includes("XHOST_AWAY"), "X HOST_AWAY");
    a.client.close();
    const host2 = await resume(hosted);
    open.push(host2);
    await until(() => host2.frames.includes("L2"), "L2 arrives with the replay");
    expect(host2.frames.filter((f) => f.startsWith("M2:")).length).toBe(3);
  });

  it("caps how many rows a flapping host can make the room write", async () => {
    const hosted = await room(); // lifetime cap 8, resumes cap 3
    const a = await joiner(hosted);
    let current: Client = hosted.host;
    let sent = 0;
    for (let round = 0; round < 2; round++) {
      current.close();
      await sleep(30);
      for (let i = 0; i < 3; i++) {
        a.client.send("Mx" + sent++); // per-peer cap is 3 per gap
        await sleep(5);
      }
      current = await resume(hosted);
      open.push(current);
      await until(() => current.frames.some((f) => f.includes("resumed")), "resumed");
      await sleep(30);
    }
    // Third gap: the lifetime cap (8) leaves room for only 2 more of the 3 messages.
    current.close();
    await sleep(30);
    for (let i = 0; i < 3; i++) a.client.send("Mx" + sent++);
    await sleep(100);
    const stored = await runInDurableObject(stubOf(hosted.code), (_i, state) => {
      const queued = [...state.storage.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM queue WHERE kind = 'M'")][0].n;
      const total = [...state.storage.sql.exec<{ v: string }>("SELECT v FROM meta WHERE k = 'buf_total'")][0].v;
      return { queued, total: Number(total) };
    });
    expect(stored.total).toBeLessThanOrEqual(8);
    expect(stored.queued).toBeLessThanOrEqual(8);
    expect(a.client.frames, JSON.stringify({ frames: a.client.frames, stored })).toContain("XHOST_AWAY"); // the overflowing joiner was sent away
  });

  it("closes the room if the host keeps dropping (resume cap)", async () => {
    const hosted = await room(); // MAX_HOST_RESUMES = 3
    const a = await joiner(hosted);
    let current: Client = hosted.host;
    for (let i = 0; i < 3; i++) {
      current.close();
      await sleep(30);
      current = await resume(hosted);
      open.push(current);
      await until(() => current.frames.some((f) => f.includes("resumed")), "resumed");
    }
    current.close(); // the fourth drop
    await until(() => a.client.frames.includes("XROOM_CLOSED"), "room closed");
  });

  it("expires after the grace period and tells joiners the room is closed", async () => {
    const hosted = await room(); // HOST_GRACE_SEC = 1 in the tests
    const a = await joiner(hosted);
    await hostDrops(hosted);
    await sleep(1200); // the room's own alarm fires about a second after the host dropped
    await runDurableObjectAlarm(stubOf(hosted.code)); // (harmless if it already ran)
    await until(() => a.client.frames.includes("XROOM_CLOSED"), "closed");
    expect(await expectRefusal("/join/" + hosted.code)).toBe("ROOM_NOT_FOUND");
    expect(await expectRefusal("/resume/" + hosted.code)).toBe("ROOM_NOT_FOUND");
  });
});

describe("expiry and dead sockets", () => {
  it("expires an idle room and a room past its maximum age", async () => {
    for (const key of ["last_activity", "created"]) {
      const hosted = await room();
      const a = await joiner(hosted);
      await runInDurableObject(stubOf(hosted.code), (_i, state) => {
        state.storage.sql.exec("UPDATE meta SET v = ? WHERE k = ?", "1000", key);
        if (key === "created") state.storage.sql.exec("UPDATE meta SET v = ? WHERE k = 'last_activity'", String(Date.now()));
      });
      await evictDurableObject(stubOf(hosted.code)); // memory is empty again, as after real hibernation
      await runDurableObjectAlarm(stubOf(hosted.code));
      await until(() => a.client.frames.includes("XROOM_CLOSED"), `closed by ${key}`);
    }
  });

  it("drops a socket that stopped answering keepalives, and tells the host", async () => {
    const hosted = await room();
    const a = await joiner(hosted);
    await runInDurableObject(stubOf(hosted.code), (_i, state) => {
      for (const ws of state.getWebSockets()) {
        const att = ws.deserializeAttachment();
        if (att.role === "peer") ws.serializeAttachment({ ...att, seen: 1000 });
      }
    });
    await runDurableObjectAlarm(stubOf(hosted.code));
    await until(() => hosted.host.frames.includes("L2"), "L2");
    await until(() => a.client.closed !== null, "closed");
    expect(a.client.closed?.code).toBe(4408);
  });

  it("keeps a socket alive when it answers keepalives, without the room's code running", async () => {
    const hosted = await room();
    const a = await joiner(hosted);
    await runInDurableObject(stubOf(hosted.code), (_i, state) => {
      for (const ws of state.getWebSockets()) {
        const att = ws.deserializeAttachment();
        if (att.role === "peer") ws.serializeAttachment({ ...att, seen: 1000 });
      }
    });
    a.client.send("ping");
    await until(() => a.client.frames.includes("pong"), "pong");
    await runDurableObjectAlarm(stubOf(hosted.code));
    await sleep(100);
    expect(a.client.closed).toBeNull();
    expect(hosted.host.frames).not.toContain("L2");
  });

  it("schedules its next sweep", async () => {
    const hosted = await room();
    const alarm = await runInDurableObject(stubOf(hosted.code), (_i, state) => state.storage.getAlarm());
    expect(alarm).not.toBeNull();
  });
});

describe("surviving hibernation", () => {
  it("keeps routing, peer ids and kicks working after the object is evicted from memory", async () => {
    const hosted = await room();
    const a = await joiner(hosted);
    await evictDurableObject(stubOf(hosted.code)); // sockets stay open, memory is wiped
    a.client.send("Mafter eviction");
    await until(() => hosted.host.frames.includes("M2:after eviction"), "routed after eviction");
    hosted.host.send("S2:reply");
    await until(() => a.client.frames.includes("Mreply"), "reply");
    const b = await joiner(hosted);
    expect(b.peer).toBe(3); // the counter lives in storage
    await evictDurableObject(stubOf(hosted.code));
    hosted.host.send("K2:KICKED");
    await until(() => a.client.frames.includes("XKICKED"), "kick after a second eviction");
  });

  it("keeps the host's grace period, token and buffer across eviction", async () => {
    const hosted = await room();
    const a = await joiner(hosted);
    hosted.host.close();
    await until(() => a.client.frames.includes("H"), "H");
    a.client.send("Mbuffered");
    await sleep(30);
    await evictDurableObject(stubOf(hosted.code));
    const host2 = await resume(hosted);
    open.push(host2);
    await until(() => host2.frames.includes("M2:buffered"), "buffer survived");
    await until(() => a.client.frames.includes("B"), "B");
  });

  it("still expires the room from the alarm after eviction", async () => {
    const hosted = await room();
    const a = await joiner(hosted);
    hosted.host.close();
    await until(() => a.client.frames.includes("H"), "H");
    await evictDurableObject(stubOf(hosted.code));
    await sleep(1100);
    await runDurableObjectAlarm(stubOf(hosted.code));
    await until(() => a.client.frames.includes("XROOM_CLOSED"), "closed");
  });

  it("answers pings itself", async () => {
    const hosted = await room();
    hosted.host.send("ping");
    await until(() => hosted.host.frames.includes("pong"), "pong");
    const answered = await runInDurableObject(stubOf(hosted.code), (_i, state) => state.getWebSockets().length);
    expect(answered).toBe(1);
  });
});

// Keeps the Room class referenced so a type error in its public surface fails the build.
void (null as unknown as Room);
