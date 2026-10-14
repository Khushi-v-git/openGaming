# Networking and session foundation (core/)

How a game hosts and joins. Games never touch sockets: they get a `LobbyHost` or
`LobbyClient` and exchange plain-data messages.

## Layers

```
 lobby_scene.tscn           UI only: shows state, emits intents
 LobbyHost / LobbyClient    lobby controllers (core/lobby)
 LobbyLogic                 pure rules: state + action -> Result (no nodes, no network)
 HostSession / ClientSession  handshake, players, limits, liveness (core/session)
 Transport                  the one networking interface (core/net)
   DirectWsTransport        ws:// on a configurable port (LAN, IP, playit.gg tunnel)
   LoopbackTransport        in-memory, one process (tests, hot-seat)
   FakeRelayTransport       in-memory relay model (proves relay transports fit)
 TransportFactory           the only place that names concrete transports
```

The active transport is chosen by config (`{"transport": "direct_ws", "port": 24680}`),
never by an import in lobby or game code.

## Messages

Every message is `{type, protocol_version, payload}`, plain JSON data (`Envelope`).
Numbers come back from JSON as floats; `Envelope.parse` turns integral ones back into ints.
Messages over 64 KB are rejected before parsing.

| type | direction | meaning |
|---|---|---|
| `hello` | client > host | `app_version, game_id, player_name, [player_id, rejoin_token]` |
| `welcome` | host > client | `player_id, rejoin_token` |
| `reject` | host > client | `code, message`, then the host closes the connection |
| `ping` / `pong` | both | liveness; any message also counts as a sign of life |
| `lobby_action` | client > host | `{action: {type, ...}}` (set_ready, set_name, leave, start, kick) |
| `lobby_state` | host > all | `{lobby: {...}}`, the full lobby after every change |
| `lobby_error` | host > one | an action was refused: `code, message, action` |
| `session_end` | host > client | `code, message`: HOST_CLOSED, KICKED, LEFT, REPLACED, RATE_LIMITED... |
| `game_action` / `game_state` | both | game traffic; opaque to core |

Error codes are in `core/net/error_codes.gd`. The handshake checks, in order: protocol
version, game id, app version (all exact in v1), name. Unknown ids and wrong tokens get
the same `BAD_TOKEN` answer.

## Limits on the host (the tunnel address is public)

- WebSocket upgrades in progress: `max_pending` (8) and `max_connections` (32), 5 s timeout.
- Peers that have connected but not said hello: `max_pending_handshakes` (8), 5 s timeout.
- Per-peer token bucket: burst 30, 20 messages/s; flooding gets the peer removed.
- Binary frames, bad JSON and oversized messages drop the peer (direct WebSocket).
- Liveness: the host pings every 5 s and drops a silent peer after 15 s; clients treat 20 s
  of host silence as a lost host. `WebSocketPeer.heartbeat_interval` is set only as a
  keepalive for idle tunnels; the application ping is what detects dead peers.

## Reconnect and rejoin

Each player has a stable `player_id` and a secret `rejoin_token`. If a connection drops the
host keeps the player (in a started game the slot stays, marked disconnected; in the open
lobby the seat is freed). The player comes back with `hello` carrying `player_id` and
`rejoin_token`, and the host:

1. checks the token, then asks the lobby (`rejoin_policy`): left players are refused
   (`PLAYER_LEFT`), a freed seat must still be free (`ROOM_FULL`);
2. replaces a stale connection for that player if the host has not noticed it died;
3. rotates the token; the previous one stays valid until the player's first message on
   the new connection, so a lost `welcome` cannot lock them out;
4. resends the full lobby state and, mid-game, a `game_state` with the player's own
   view from `LobbyHost.game_view_provider` (the only allowed full-state resend, rule 11).

Kicked players and players who left the open lobby lose their identity.

## Saving and resuming

`LobbyHost.snapshot(game_state)` returns plain data (`SessionSnapshot`): the lobby, every
player's identity **including rejoin tokens**, and the game's own state. Save it with
`SessionSnapshot.save_file("user://saves/...", snapshot)` (atomic write).

**Saves are private.** A save lets whoever holds it act as any player in it. Keep it in the
user's own folder and only give it to someone you would trust to host the game. Tokens are
rotated on each player's first rejoin after a resume, so a leaked save stops working once
everyone has come back.

To resume: create a fresh `LobbyHost`, call `restore(saved, as_player_id)` **before**
`start()`, then host as usual. Any saved player can be the host; the previous host rejoins
as an ordinary player using `SessionSnapshot.identity_of(saved, their_id)`. Everyone else
is offline until they rejoin with the identity they were given. A save only loads into the
same `game_id` and the same app version.

## Adding a transport (e.g. the cloud relay)

Subclass `Transport` and honour the contract in `core/net/transport.gd`, then add it to
`TransportFactory`. Prove it by adding a `TransportEnv` and two thin test files that extend
`transport_contract.gd`, `session_contract.gd` and `lobby_contract.gd`; those suites must
pass unchanged. A relay only forwards messages: the host stays the single authority.

## Debug logging

In debug builds every message sent or received is logged as
`[net HH:MM:SS.mmm] -> player=p2 peer=2 type=lobby_state` (never payloads, so tokens and
hidden information stay out of logs). Change `MessageLog.sink` to redirect, or set
`MessageLog.enabled = false`.

## Tests

`docs/running-tests.md` explains how to run them. `tests/core/`:

- pure units: envelope, handshake, rate limiter, address parser, player registry,
  lobby logic, snapshot;
- contract suites run once per transport (loopback, fake relay, direct WebSocket on
  localhost): `transport_contract`, `session_contract`, `lobby_contract`;
- `test_lobby_scene.gd` drives two lobby screens like two players.

Network tests use `NetWait` (poll until a condition holds or N frames pass) and a
`FakeClock`, so timeouts are tested without waiting.
