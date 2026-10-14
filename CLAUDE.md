# onlyGaming

Free, open-source desktop board and card games for playing with friends.
One Godot application containing many games. One player hosts, the others
join. Starting game: Snakes and Ladders.

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
  net/                     transport interface and implementations
  lobby/                   host/join/ready, player slots
  session/                 handshake, reconnect, save/load
  ui/                      shared UI kit (themes, buttons, panels)
  registry/                game registry and manifest loader
  assets/                  shared art, fonts, icons, dice, paper textures
games/
    climb_and_slither/
    rules/                 pure logic, no nodes
    ui/                    scenes and scripts
    assets/                game-specific art
    tests/
main/                      home screen, game picker, app settings
docs/
```
- core/ must never import from games/ or main/.
- A game depends only on core's public interfaces and never on another game.
- Games register through a manifest (id, display name, icon, min/max players,
  rules class, UI scene). The home screen is built from the registry. Adding a
  game must not require editing core/.
- Shared art lives in core/assets/. Game-specific art stays in the game folder.

## Architecture rules (do not violate)

1. **Host-authoritative.** The host's app runs the only copy of the game rules
   and state. Clients send actions ("roll", "play_card 3"), never state
   changes. The host validates every action, applies it, and broadcasts the
   result.

2. **Game rules are pure logic.** Rules live in plain scripts that extend
   RefCounted, with no dependency on scene nodes, UI, networking or timers.
   Core shape: `apply(state, player_id, action) -> new_state | error`. All
   randomness comes from a seeded RandomNumberGenerator passed in, so results
   are reproducible. Rules must be unit-testable with no window and no network.

3. **Transport is an interface.** All networking goes through one small
   interface: `send(peer_id, message)`, `broadcast(message)`, `on_message`,
   `on_peer_connected`, `on_peer_disconnected`. Game and lobby code must never
   reference a concrete socket, IP address or Godot RPC. Implementations
   (WebSocket/TCP for direct and tunnel use, a relay client later) are
   interchangeable behind the interface.

3a. **Relay-ready transport.** The transport interface is expressed as
    session operations, not socket operations:
    - `host_session(config) -> session_info` (returns the address or room code
      to share)
    - `join_session(address_or_code, config)`
    - `leave()`, plus the send/broadcast/event methods from rule 3.
    A direct implementation listens on a port. A relay implementation connects
    outbound to a relay and registers a room. Game, lobby and session code see
    no difference. Peers are identified by an opaque `peer_id` assigned by the
    transport, never by IP or socket. The active transport is chosen by
    configuration, never by an import in game or lobby code. The host remains
    the single authority regardless of transport: a relay only forwards
    messages.

4. **Messages are plain data.** Every message is a JSON-serializable dict with
   `type`, `protocol_version` and a payload. No engine objects or binary blobs.
   Do not use Godot's high-level @rpc for game logic, because it couples the
   game to one transport.

5. **Address is configuration.** The join screen takes an address string
   (IP:port, hostname:port, or later a room code). Never hardcode hosts, ports
   or tunnel URLs. The host's listening port is a setting.

6. **Version handshake.** On connect, peers exchange `app_version`, `game_id`
   and `protocol_version`. Mismatches produce a clear in-app error, never
   undefined behavior.

7. **Reconnect support.** Every player has a stable `player_id` and a secret
   rejoin token. If a connection drops, the player can rejoin and the host
   resends the full current state. The host must tolerate a disconnected
   player without crashing or ending the game.

8. **Serializable state.** Game state must be fully serializable to plain data
   so any player can save a game, load it, and resume it as host.

9. **Hidden information stays on the host.** Hands, face-down choices and
   secret keys are never sent to players who must not see them. Send each
   player only their own view: `view_for(state, player_id)`. Simultaneous
   choices are collected, then revealed together.

10. **Deterministic, host-run physics.** For any physics-based game (e.g.
    carrom), only the host simulates. Clients send the input; the host
    broadcasts the resulting board state or keyframes. Clients animate but
    never decide outcomes.

11. **Small, infrequent messages.** Send actions and state snapshots or deltas
    on turn boundaries. Never stream per-frame data.

12. **UI never decides rules.** UI scenes display state and emit actions. They
    contain no game logic.

## Networking and hosting model
- Any player can host. Every copy of the app contains both host and client
  roles.
- The host's app listens on a configurable port. Remote friends reach it
  through a tunnel (playit.gg by default) or by LAN/IP. Joiners only paste an
  address and a player name. Only the host does any network setup.
- Start with direct address plus playit.gg. A cloud relay (e.g. Cloudflare
  Workers + Durable Objects, WebSocket, room codes) may be added later as a
  second transport. It must require no changes to game code.
- The host needs a PC that stays on and awake. If the host leaves for good the
  game ends unless it was saved (see rule 8).

## Climb and Slither (first game)
- Board data (snake and ladder start/end squares) lives in a data file, not in
  rules code. Validate it: no snake or ladder starts on square 1 or 100, no
  square is both, and chains must terminate.
- House rules are settings, not hardcoded: exact roll needed to finish on 100,
  extra turn on a 6.
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
  shares the same depth.
- Fonts must have a free license (OFL / Google Fonts).
- Keep assets small: export at display size, use OGG not WAV, no oversized
  source files in the repo.
- UI is built with Godot Control containers (VBox/HBox/Grid/Margin) and scales
  from 1920x1080 down to 1280x720. Design tokens (colors, spacing, radii)
  live in the shared theme in core/ui.

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
  tunnel testing.
- Test order: unit tests, hot-seat (one window), loopback, LAN, then a real
  tunnel with a friend on another network.
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
- Run the test suite before saying a task is done, and report what was run.
- Prefer small, focused commits with clear messages.
- Use typed GDScript (type hints on variables, parameters and returns).
- Keep files small and single-purpose; put shared code in core/, not copies in
  games.