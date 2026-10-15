# The relay

Players reach the host with a 6-character room code instead of an address, so nobody needs a
port forward or a tunnel. The host and every joiner connect **outward** over `wss://` to a relay:
a Cloudflare Worker plus one SQLite-backed Durable Object per room (`relay/cloudflare/`). The relay
is a dumb forwarder. It never looks at payloads, only at one routing character per frame, and the
host stays the single authority. Direct (`ip:port`) mode still works and is the fallback.

## Setup and local development

Needs Node 22+ (`node -v`).

```
cd relay/cloudflare
npm install
npm test                  # Node-side tests in the Workers runtime
npm run dev               # wrangler dev --local on http://127.0.0.1:8787
curl http://127.0.0.1:8787/health
```

To point the game at a local relay, set the relay URL to `ws://127.0.0.1:8787` (see "Settings").
`scripts/run_integration_tests.sh` runs the contract suites against it (docs/running-tests.md).

### Hibernation check

`relay/cloudflare/tools/hibernation_check.mjs` proves, against `wrangler dev`, that:

- keepalive `ping` frames are answered by the runtime without running the room's code and without
  waking it (0 wake-ups and 0 handler runs over a 30 s pings-only window);
- after a silent period the room object really hibernates (its constructor runs again on the next
  message) and its state (peer ids, routing) survives.

```
cd relay/cloudflare
npx wrangler dev --local --port 8787 --var DEBUG_LIFECYCLE:1 --var SWEEP_SEC:100000 --var DEAD_SEC:100000 > dev.log 2>&1 &
node tools/hibernation_check.mjs ws://127.0.0.1:8787 dev.log
```

The sweep alarm is pushed far away only so it cannot wake the room during the experiment; its cost
is in the estimate below. Local `wrangler dev` does not enforce free-plan limits.

## Wire format

Defined in `relay/cloudflare/src/frames.ts` and `core/net/relay_transport.gd`. Joiners send
`M<payload>`; the host sends `S<peer>:<payload>`, `K<peer>:<code>` (disconnect, delivered after
everything sent before) and `Q` (leaving for good). The relay sends `M`, `J<peer>`, `L<peer>`, `H`
(host away), `B` (host back), `X<code>` (final) and `C<json>` control frames (hosted, joined,
resumed, error). Peer ids start at 2 and are never reused. Refusals complete the WebSocket upgrade,
send one error frame and close, because Godot cannot read the HTTP status of a refused upgrade.

## Keepalive and dead peers

The session layer's own pings are not sent through the relay (`keepalive_policy()` returns zeros):
every message costs quota and wakes the room. Instead each socket sends `ping` every 15 s, which the
runtime answers `pong` itself. A client that hears nothing for 45 s treats the link as dead (a joiner
sees the host lost; a host reconnects). A relay alarm sweeps every 30 s and drops sockets with no
keepalive for 50 s. All of it is configurable (`wrangler.jsonc` vars, and `ping_msec` /
`watchdog_msec` in the transport config). Dead peers are noticed in roughly 50 to 80 s.

## Host away, resume, restart

If the host's socket drops without a `Q`, the room is held for `HOST_GRACE_SEC` (60 s). Joiners get
`H` and the transport emits `link_state_changed("host_away")`; their messages are buffered (bounded:
32 per joiner, 128 KB, 200 per room lifetime, so a flapping host cannot burn the daily row limit;
a room also allows at most 20 resumes). The host reconnects with its secret token, gets the buffer
replayed in order, and joiners get `B`. Anything that fails (overflow, expiry, bad token) ends in the
normal path: joiners see the host lost and offer Rejoin.

The host token lives only in memory. **If the host app restarts it cannot resume the room.** Loading
a saved game creates a new room with a **new code**, and players rejoin with their session tokens
(rule 7).

## Free-plan limits (Cloudflare, checked October 2026)

Workers Free: 100,000 requests/day (all Workers and Durable Object requests, resets 00:00 UTC),
10 ms CPU per HTTP request. Durable Objects (SQLite) on Free: 13,000 GB-s/day duration, 5 million rows
read/day, 100,000 rows written/day, 5 GB storage. Incoming WebSocket messages count 20:1 as requests;
outgoing messages are free; an idle object eligible for hibernation is not billed for duration;
auto-response (`setWebSocketAutoResponse`) uses no wall-clock time; each `setAlarm` is one row
written and an alarm invocation counts as a request. Sources: developers.cloudflare.com
(durable-objects/platform/pricing and limits, workers/platform/limits).

**Estimate, 4 players, one hour, ping 15 s, sweep 30 s:** game messages about 1,200 incoming / 20 =
~60 requests; keepalive 4 sockets x 240 / 20 = ~48; sweep alarm 120; connects ~5. **About 233
requests/hour, so roughly 430 game-hours a day against 100,000 requests/day.** Rows written are about
130/hour. Duration is only active handler time (well under 10 GB-s/hour); even a never-idle object is
at most 450 GB-s/hour, so at least 28 game-hours a day. These are estimates, not measurements.

**When a limit is hit:** Workers returns Error 1027 for new requests; what a Durable Object does at its
own limit is not documented and was deliberately not tested. The app maps any unexpected close or error
to `RELAY_BUSY` ("The relay is busy or cannot be reached right now... or use a direct address"). Existing
games may drop. Use direct mode (below) until the quota resets.

### Accepted risk

Anyone who knows the relay URL can burn the daily request quota. This is accepted. Mitigations: room
codes cannot be enumerated cheaply (31^6 is about 8.9e8 codes), failed lookups write nothing, and direct
mode is a tested fallback. The Rate Limiting binding (`ratelimits` in the wrangler config; the Worker uses
it only if it is bound as `JOIN_LIMITER`) is optional: its availability on the free plan is **unverified**
(the docs do not say), and it is per-location and "permissive". Check it on your own account before
relying on it.

## Trust model

TLS ends at Cloudflare, so **the relay operator can read all traffic, including rejoin tokens in
welcome messages, and can impersonate players. The operator is trusted.** The room code and host token
are the only access control; the host's admission policy still applies to joiners. Run your own relay if
you do not trust someone else's.

## Direct mode is the fallback

Direct `ip:port` (LAN, port forward) is unchanged and its contract suites still run in the normal test
run. Hosting by direct address is a choice in app settings (`host_via` = `direct`); joining accepts
either a room code or an address (a code is 6 letters/digits with no 0/O/1/I/L; anything with `.` or
`:` is direct; a `relay:` prefix forces the relay).

## Settings

**In the app:** the lobby's start screen has a Connection section with a relay address box, a
"Host with" choice (room code or direct address) and a Test button that opens and closes a room on
that relay and tells you if it works. Paste any relay's address, in any form (`name.workers.dev`,
`https://...`, `wss://...`; a bare `localhost`/IP address means a local `ws://` relay). It is
remembered for next time, so playing with a different group means pasting a different address
once, never editing code. Joiners need the box filled too (the host tells them the address along
with the room code) unless the build ships a default.

The relay URL has one committed default: the project setting `onlygaming/network/relay_url` in
`project.godot`. A player overrides it in `user://settings.cfg` (`[network] relay_url`, via `AppSettings`)
without touching the repo. Blank the committed default before the repo goes public (README release
checklist). Never commit account ids, tokens or `.dev.vars`.

## Deploying (commands, not yet run)

Use your own free Cloudflare account.

```
cd relay/cloudflare
npx wrangler login
npx wrangler deploy
```

The first deploy asks you to pick a `workers.dev` subdomain; the relay is then at
`wss://onlygaming-relay.<your-subdomain>.workers.dev`. Deploying restarts all rooms and disconnects
existing sockets. Check it:

```
curl https://onlygaming-relay.<your-subdomain>.workers.dev/health
```

Then set the URL (project setting, or in app settings) and run the wss probe below. To use someone
else's relay, only the URL changes.

### wss probe from Godot

Proves Godot's default TLS validation reaches the deployed relay and that a room can be created. Save as
`probe.gd`:

```gdscript
extends SceneTree

func _initialize() -> void:
	var ws: WebSocketPeer = WebSocketPeer.new()
	print("connect: ", error_string(ws.connect_to_url(OS.get_cmdline_user_args()[0] + "/host")))
	var start: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 8000:
		ws.poll()
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN and ws.get_available_packet_count() > 0:
			print("first frame: ", ws.get_packet().get_string_from_utf8().left(60))  # C{"t":"hosted","code":"..."
			break
		OS.delay_msec(20)
	ws.close()
	quit()
```

```
"$GODOT_BIN" --headless --path . -s probe.gd -- wss://onlygaming-relay.<your-subdomain>.workers.dev
```

## Test doubles vs the real relay

`FakeRelay` (in-memory, used by `FakeRelayTransport`) and `ScriptedRelay` (localhost WebSockets, used by
`test_relay_transport.gd`) match the real relay on peer ids from 2, star topology, ordering, room
registration, kick-then-disconnect and the error frames the transport maps. They differ: `FakeRelay` is
synchronous and has its own API, codes like `ROOM-0001`, and no tokens or resume. Neither has the size
cap, rate limit, handshake timeout, room cap, expiry, grace period, buffering or hibernation; those are
covered by `relay/cloudflare/test` and the integration tier. `ScriptedRelay` is a Godot server, which
drops a frame that arrives together with a close frame, so the host's `Q` is only tested on the real relay.
