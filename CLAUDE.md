# openGaming

Free, open-source desktop board and card games for playing with friends.
One Godot application containing many games. One player hosts, the others
join. Starting game: Climb and Slither (a Snakes and Ladders game).

## Tech stack and environment
- Godot 4.x (standard build), GDScript, Compatibility renderer, 2D only.
- Editing in VS Code with the godot-tools extension; the Godot editor must be
  running for language-server features.
- Git monorepo (one repo, one exported app, all games inside).
- Test framework: GUT (or gdUnit4, pick one and keep it). Tests must run from
  the command line in headless mode.
- Everything must stay free and open source: no paid services, proprietary
  SDKs, or required accounts for players.

## Repo layout
```
core/                      shared code, used by every game
  net/                     transport interface and implementations (direct, relay client)
  lobby/                   host/join/ready, player slots
  session/                 handshake, reconnect, save/load
  ui/                      shared UI kit (themes, buttons, panels)
  registry/                game registry and manifest loader
  game/                    game-agnostic play code: game controllers, event timeline
  util/                    small shared helpers (Prng)
  assets/                  shared art, fonts, icons, dice, paper textures
games/
  climb_and_slither/       one folder per game, same layout in each
    manifest.json          registry entry (see below)
    data/                  data files (boards, tables)
    rules/                 pure logic, no nodes
    ui/                    scenes and scripts
    assets/                game-specific art
    tests/
main/                      home screen, game picker, app settings
tests/
  core/                    tests for core/ (games keep theirs in games/*/tests)
  main/                    tests for main/
addons/
  gut/                     GUT test framework (approved addon)
relay/
  cloudflare/              the relay: a Cloudflare Worker + Durable Object (TypeScript, Node tests)
tests_integration/         contract suites against a real local relay (scripts/run_integration_tests.sh)
docs/
```
- core/ must never import from games/ or main/.
- A game depends only on core's public interfaces and never on another game.
- Games register through a manifest (id, display name, icon, min/max players,
  rules class, UI scene, optional settings scene). The home screen is built from the registry. Adding a
  game must not require editing core/. `ui_scene` is optional in the manifest
  while a game is in development; the home screen lists only games that have
  one.
- Shared art lives in core/assets/. Game-specific art stays in the game folder.
- Adding a game follows `docs/adding-a-game.md` (decide, write the rules down,
  design the state/actions/events/views, then rules, tests, network proof, UI,
  manifest). A game needs no change to core/; several players acting at once
  (trading, auctions) is accepted by the network layer but its UI convention
  is not decided yet: ask before changing core for it.

## Architecture rules (do not violate)

1. **Host-authoritative.** The host's app runs the only copy of the game rules
   and state. Clients send actions ("roll", "play_card 3"), never state
   changes. The host validates every action, applies it, and broadcasts the
   result.

2. **Game rules are pure logic.** Rules live in plain scripts that extend
   RefCounted, with no dependency on scene nodes, UI, networking or timers.
   Core shape: `apply(state, player_id, action, active_players) -> Result`.
   `active_players` is the list of player ids who are present and still in the
   game, in seat order (`LobbyHost.active_players()`); turn rotation must skip
   everyone else (see `TurnOrder`), and absent players keep their seat and get
   their turn back when they return. A game declares `min_active_players` in
   its manifest (default: `min_players`), the fewest present players it can run
   with; the host cannot "continue without waiting" below it. Result is a
   plain dict `{ok: bool, state: Dictionary, error: {code, message}}` (`state`
   when ok, `error` when not; on error the input state is unchanged). All
   randomness comes from the shared `Prng` (core/util), a seeded generator
   that gives the same numbers on every Godot version. Its seed and state live
   in the game state as decimal strings (64-bit values do not survive JSON as
   numbers) and are host-only: they never appear in `view_for` output, and the
   host broadcasts views, never raw state. Results are reproducible. Rules
   must be unit-testable with no window and no network.

   Every game's rules class extends `GameRules` (core/game, itself a
   RefCounted) and fulfils its contract, so core never needs to know which game
   it runs: `new_game(player_ids, setup, settings, seed)` (`setup` is
   game-specific start data such as a board; `default_setup()` supplies the
   usual one), `apply(...)` as above,
   `settle(state, active_players)` (hand the turn on when the current player
   dropped; the base default does nothing), `view_for(state, player_id)`,
   `validate_state(state)`, and three queries that work on a state or a view:
   `is_finished`, `current_player` ("" when none) and `winner`. Results carry
   `events`, an ordered list of plain dicts with a `type`, that tell a UI what
   happened. Screens never call rules directly: they talk to a `GameController`
   (`LocalGameController` for hot-seat, network controllers later; only the
   host or hot-seat may `rematch()`), which hands
   them batches `{seq, reason, events, view}`; `EventTimeline` plays a batch's
   events one at a time and ends on the batch's view. `core/game` contains no
   game-specific code (a test checks this against a tiny test-only game). A
   game's `ui_scene` root has `setup(controller, players)` and the signals
   `leave_requested` and `game_ended`; an optional `settings_scene` has
   `settings()` and a `changed(settings)` signal (the lobby shows it to the
   host and shows guests the read-only `GameRules.describe_settings`; the
   lobby checks settings with `GameRules.validate_settings`). Networked games
   use `GameHost` (the host's only copy of the rules and state; it sends each
   player a batch `{seq, reason, events, view}` and answers illegal actions
   with `game_error`, changing nothing), `GameClient` and
   `NetworkGameController`; the host alone can rematch or end the game
   (`end_game` returns everyone to the lobby).

3. **Transport is an interface.** All networking goes through one small
   interface: `send(peer_id, message)`, `broadcast(message)`,
   `disconnect_peer(peer_id)`, `poll()` (the owner calls it every frame), and
   the signals `message_received`, `peer_connected`, `peer_disconnected`,
   `join_succeeded`, `join_failed`, `session_ready`, `host_failed` (joining
   and hosting are asynchronous). On a client the
   host is always `HOST_PEER_ID`. Game and lobby code must never
   reference a concrete socket, IP address or Godot RPC. Implementations
   (WebSocket/TCP for direct use, a relay client) are interchangeable behind
   the interface. Two optional additions: the signal
   `link_state_changed(state)` (`LINK_OK`, `LINK_HOST_AWAY`,
   `LINK_RECONNECTING`) is a UI notice from transports whose link can degrade
   without the session ending (a relay holding a room); sessions never depend
   on it. And `keepalive_policy()` says whether the session layer should send
   its own pings over this transport (a direct transport relies on them; a
   relay must not carry them). In session options, 0 turns pings and the
   silence timeouts off; explicit options win over the transport's policy.

3a. **Relay-ready transport.** The transport interface is expressed as
    session operations, not socket operations:
    - `host_session(config)` starts hosting. It returns a failure only if
      hosting could not even start (bad config, port in use); otherwise the
      transport later emits exactly one of `session_ready(info)` (info has the
      `address` or room code to share, and the transport `kind`) or
      `host_failed(reason)`. A direct transport is ready at its next `poll()`;
      a relay is ready once the relay has registered the room, which takes a
      network round trip. UI shows a "starting" state with Cancel until then.
    - `join_session(address_or_code, config)` (result via `join_succeeded` or
      `join_failed`)
    - `leave()`, plus the send/broadcast/event methods from rule 3.
    Events are only emitted from `poll()`.
    A direct implementation listens on a port. A relay implementation connects
    outbound to a relay and registers a room. Game, lobby and session code see
    no difference. Peers are identified by an opaque `peer_id` assigned by the
    transport, never by IP or socket. The active transport is chosen by
    configuration, never by an import in game or lobby code. The host remains
    the single authority regardless of transport: a relay only forwards
    messages.

    The relay (relay/cloudflare) is a dumb forwarder: no game logic, a one-byte
    routing header, payloads are opaque text (the 64 KB cap applies to the
    payload; the relay allows a little extra for its header). Its URL is
    configuration: the project setting `onlygaming/network/relay_url`, which a
    player can override in the app settings, and nowhere else. Relay
    transports do not carry the session's app-level pings: each socket sends
    its own cheap keepalive that the relay answers without waking up, and a
    quiet link is declared dead after a configurable watchdog time. If the host
    drops, the relay holds the room for a grace period so the host can resume
    with its secret room key (kept in memory only); joiners get
    `link_state_changed` meanwhile, and if the room expires they see the usual
    host loss. A restarted host cannot resume: a resumed saved game opens a
    new room with a new code and players rejoin it with their session tokens.
    `session_ready`'s info may carry `share_label` ("address" or "room code")
    so the lobby can name what it shows. The relay operator can read all
    traffic, including rejoin tokens, and is trusted.

4. **Messages are plain data.** Every message is a JSON-serializable dict with
   `type`, `protocol_version` and a payload. No engine objects or binary blobs.
   Do not use Godot's high-level @rpc for game logic, because it couples the
   game to one transport.

5. **Address is configuration.** The join screen takes an address string
   (IP:port, hostname:port, or later a room code). Never hardcode hosts, ports
   or tunnel URLs. The host's listening port is a setting.

6. **Version handshake.** On connect, peers exchange `app_version` and
   `protocol_version`, and the host answers with its `game_id`. Joiners do not
   pick a game: `game_id` is optional in the client's hello (if sent, it must
   match), and the host's welcome and every reject carry the host's `game_id`
   and `app_version`. If the client's app has no such game it shows a clear
   error (`UNKNOWN_GAME`) and leaves. In v1 `app_version` and
   `protocol_version` must match exactly for live sessions (loosening
   `app_version` to major.minor is a later decision). Mismatches produce a
   clear in-app error with an error code, never undefined behavior.

7. **Reconnect support.** Every player has a stable `player_id` and a secret
   rejoin token. If a connection drops, the player can rejoin and the host
   resends the full current state. The host must tolerate a disconnected
   player without crashing or ending the game. In a started game a player who
   drops or leaves keeps their seat and the game pauses; the host decides:
   wait, "continue without waiting" (the player may still return), or remove
   them for good. A returning player who lost their saved identity (restarted
   app) may claim their seat by typing the same name; the host is asked and
   must approve. A seat that is online, or was removed, can never be claimed.
   While paused the host refuses players' game actions (`GAME_PAUSED`).

8. **Serializable state.** Game state must be fully serializable to plain data
   so any player can save a game, load it, and resume it as host. A save has
   its own `save_version`, independent of `app_version`, so app upgrades do
   not orphan saves; there are no migrations yet, so a save with an unknown
   `save_version` is refused with `UNSUPPORTED_SAVE`. A game's own state should
   carry its own version number for the same reason. Saves contain rejoin
   tokens and are private.

9. **Hidden information stays on the host.** Hands, face-down choices and
   secret keys are never sent to players who must not see them. Send each
   player only their own view: `view_for(state, player_id)`. Simultaneous
   choices are collected, then revealed together.

10. **Deterministic, host-run physics.** For any physics-based game (e.g.
    carrom), only the host simulates. Clients send the input; the host
    broadcasts the resulting board state or keyframes. Clients animate but
    never decide outcomes.

11. **Small, infrequent messages.** Send actions and state snapshots or deltas
    on turn boundaries. Never stream per-frame data. The one allowed exception
    is a single full-state resend to a player who rejoins.

12. **UI never decides rules.** UI scenes display state and emit actions. They
    contain no game logic.

## Networking and hosting model
- Any player can host. Every copy of the app contains both host and client
  roles.
- In direct mode the host's app listens on a configurable port and friends
  reach it by LAN/IP or through a tunnel they set up themselves. Joiners only
  paste an address or room code and a player name. Only the host does any
  network setup.
- Play goes through a relay by default: the host gets a 6-character room code
  and joiners type it, with nothing to forward or tunnel. The relay is a
  Cloudflare Worker + Durable Objects on the free plan (relay/cloudflare);
  anyone can deploy their own and put its URL in the app settings. Direct
  address (LAN, IP, or a tunnel) stays supported and tested as the fallback
  for when the relay is unreachable or its free quota is used up (anyone with
  the relay's URL can use that quota; that is accepted and documented in
  docs/relay.md). Only the maintainer of a relay needs a Cloudflare account;
  players need none. The relay changes no game code.
- The host needs a PC that stays on and awake. If the host leaves for good the
  game ends unless it was saved (see rule 8).
- Closing and leaving are polite, two-step operations, because a close frame
  can overtake the last message on some transports (Godot's WebSocketPeer
  drops unread packets when a close frame arrives in the same poll):
  - `HostSession.close()` / `LobbyHost.close()` sends `session_end` to every
    player, then stops hosting once they have left or `close_grace_msec`
    passes. The owner must keep calling `poll()` until the `closed` signal
    fires. `close_now()` stops immediately; players then see a lost connection.
  - `LobbyClient.leave()` sends a `leave` action and waits (up to 1.5 s) for
    the host to close the connection; `left` fires with code `LEFT`.
    `leave_now()` drops the connection immediately and the host sees a lost
    connection instead of a leave.
  - `Transport.disconnect_peer()` must still deliver messages sent just before
    it; a transport may give the peer a short grace period to close first.

## Climb and Slither (first game)
- Board data (snake and ladder start/end squares) lives in a data file, not in
  rules code. Validate it: every start square is unique and is not square 1 or
  100 (so no square is both a snake and a ladder start); a jump's end is never
  another jump's start (no chains, no loops); snakes go down and ladders go up.
  Shared end squares are allowed. A landing triggers at most one jump. The
  last square must be reachable under every allowed settings combination (one
  die with exact finish, one die without, two dice without): a search from
  square 0 over dice moves 1 to 6 (one die) and 2 to 12 (two dice), plus the
  board's jumps, must get there. With exact finish an overshoot does not move;
  without it an overshoot lands on the last square. So six snake heads in a
  row, a trap near the start, or a lone free square before the last that two
  dice cannot finish from, are refused.
- House rules are settings, not hardcoded: exact roll needed to finish on 100,
  extra turn on a 6, number of dice. Defaults: exact finish off, extra turn on
  a 6 off, one die. With two dice, "a 6" means either die shows a 6. There is
  no cap on consecutive extra turns. Exact finish needs one die: with two dice
  the square before the last could never be finished (minimum total is 2), so
  the combination is refused.
  A fourth house rule, "need a 1 to start" (`need_one_to_start`, default off),
  keeps pawns off the board until a die shows a 1; that roll moves the pawn
  to square 1, any other roll from the start does nothing.
- The rules draw one range_int(1, 6) per die, in order. Changing the draw
  order or the Prng algorithm breaks saves and replays and requires bumping
  state_version.
- Snakes and ladders are separate sprites placed from data. Square numbers are
  drawn as labels by Godot, never baked into the board image.
- 2-4 players. Player colors: red, blue, green, yellow.

## Art and UI
- Style: simple papercut illustration. Layered cut-paper shapes with soft short
  drop shadows (light from top-left), flat solid colors, subtle paper grain,
  no outlines, no gradients, no glossy highlights.
- Palette: paper cream #F4ECD8, deep teal #1F6F6B, forest green #2F6B4F,
  saffron #F0A93B, terracotta #D2603E, rose #C94F6D, indigo #2E3A6B, ink
  #2B2A33 (tiny details only). Player colors: red #D64545, blue #3F6FD1, green
  #3FA25A, yellow #E5B93C.
- Prefer sprites without baked shadows; add shadows in-engine so every game
  shares the same depth. Do not add an in-engine shadow to a sprite that
  already has a baked one.
- Fonts must have a free license (OFL / Google Fonts). Until one is chosen the
  engine's default font is used.
- Keep assets small: export at display size, use OGG not WAV, no oversized
  source files in the repo.
- UI is built with Godot Control containers (VBox/HBox/Grid/Margin) and scales
  from 1920x1080 down to 1280x720. Design tokens (colors, spacing, radii)
  live in the shared theme in core/ui. The one intended exception is a game
  board: it is a Control that fills the rectangle a container gives it and
  places its squares, sprites and pawns by math inside it (see
  `ClimbBoardView`), because board geometry is not a container layout.
- Starting a rematch or returning to the lobby after a game ends is a host-only
  decision, like pause and remove (rule 7); clients only see the result.

## Testing requirements
- Rules have headless unit tests (no scene, no network). Snakes and Ladders
  cases: correct movement, snake and ladder jumps, turn rotation, wrong-player
  and invalid actions rejected with state unchanged, finish rule, extra turn,
  game over locks further actions, board data validation.
- Fuzz test: simulate thousands of seeded games and assert every game
  finishes and state stays valid.
- Keep a replay format (seed plus list of actions) so any bug can be
  reproduced in a test.
- A loopback test with a host and 3 simulated clients must pass before any
  network testing.
- Test order: unit tests, hot-seat (one window), loopback, the integration
  tier (contract suites on a real local relay), LAN, then the deployed relay
  with a friend on another network. The integration tier skips cleanly when
  Node or the relay's dependencies are missing.
- Log every message sent and received (timestamp, player id, type) in debug
  builds.

## Legal and naming
- Use original names, art and rules text. Do not copy the names, artwork,
  theme or rulebook wording of any commercial game. Implement mechanics only.
- Do not use reversed, misspelled or sound-alike versions of commercial game
  names.
- Public-domain or traditional games may use their real names (Snakes and
  Ladders, Ludo, Carrom, Chess, etc.). Avoid trademarked variants such as
  "Chutes and Ladders", "Parcheesi" and "Uno".
- Credit art and pattern traditions respectfully in the README. Check the
  license of any third-party or generated asset before committing it.

## Working agreements
- Rules first, screens later: rules and tests are written and passing before
  UI work starts on a game.
- Do not change the architecture rules above without asking. If a task seems
  to require breaking one, stop and explain.
- Do not add dependencies, addons or services without asking.
- Only stop processes you started yourself, tracked by PID. Never kill processes
  by name or pattern, because the user may have their own game windows running.
- Run the test suite before saying a task is done, and report what was run.
- Prefer small, focused commits with clear messages.
- Use typed GDScript (type hints on variables, parameters and returns).
- Keep files small and single-purpose; put shared code in core/, not copies in
  games.